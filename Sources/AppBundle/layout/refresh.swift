import AppKit
import Common

@MainActor
private var activeRefreshTask: Task<(), any Error>? = nil

@MainActor
func scheduleRefreshSession(
    _ event: RefreshSessionEvent,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) {
    activeRefreshTask?.cancel()
    activeRefreshTask = Task { @MainActor in
        try checkCancellation()
        try await runRefreshSessionBlocking(event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
    }
}

@MainActor
func runRefreshSessionBlocking(
    _ event: RefreshSessionEvent,
    layoutWorkspaces shouldLayoutWorkspaces: Bool = true,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) async throws {
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    if !TrayMenuModel.shared.isEnabled { return }
    try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            let nativeFocused = try await getNativeFocusedWindow()
            if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
            updateFocusCache(nativeFocused)

            if shouldLayoutWorkspaces && optimisticallyPreLayoutWorkspaces { try await layoutWorkspaces() }

            refreshModel()
            try await refresh()
            gcMonitors()

            updateTrayText()
            SecureInputPanel.shared.refresh()
            try await normalizeLayoutReason()
            if shouldLayoutWorkspaces { try await layoutWorkspaces() }
        }
    }
}

@MainActor
func runLightSession<T>(
    _ event: RefreshSessionEvent,
    _ token: RunSessionGuard,
    body: @MainActor () async throws -> T,
) async throws -> T {
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    activeRefreshTask?.cancel() // Give priority to runSession
    activeRefreshTask = nil
    return try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            let nativeFocused = try await getNativeFocusedWindow()
            if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
            updateFocusCache(nativeFocused)
            let focusBefore = focus.windowOrNil

            refreshModel()
            let result = try await body()
            refreshModel()

            let focusAfter = focus.windowOrNil

            updateTrayText()
            SecureInputPanel.shared.refresh()
            try await layoutWorkspaces()
            if focusBefore != focusAfter {
                focusAfter?.nativeFocus() // syncFocusToMacOs
            }
            scheduleRefreshSession(event)
            return result
        }
    }
}

struct RunSessionGuard: Sendable {
    @MainActor
    static var isServerEnabled: RunSessionGuard? { TrayMenuModel.shared.isEnabled ? forceRun : nil }
    @MainActor
    static func isServerEnabled(orIsEnableCommand command: (any Command)?) -> RunSessionGuard? {
        command is EnableCommand ? .forceRun : .isServerEnabled
    }
    @MainActor
    static var checkServerIsEnabledOrDie: RunSessionGuard { .isServerEnabled ?? dieT("server is disabled") }
    static let forceRun = RunSessionGuard()
    private init() {}
}

@MainActor
func refreshModel() {
    Workspace.garbageCollectUnusedWorkspaces()
    checkOnFocusChangedCallbacks()
    normalizeContainers()
}

@MainActor
private func refresh() async throws {
    // Garbage collect terminated apps and windows before working with all windows
    let mapping = try await MacApp.refreshAllAndGetAliveWindowIds(frontmostAppBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    let aliveWindowIds = mapping.values.flatMap { $0 }.toSet()

    for window in MacWindow.allWindows {
        if !aliveWindowIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false)
        }
    }
    for (app, windowIds) in mapping {
        for windowId in windowIds {
            try await MacWindow.getOrRegister(windowId: windowId, macApp: app)
        }
    }

    // Detect and register tab groups
    let mappingWithTabsEnabled = mapping.filter { $0.key.isTabDetectionEnabled }
    if !mappingWithTabsEnabled.isEmpty {
        try await refreshTabGroups(mapping: mappingWithTabsEnabled)
    }

    // Garbage collect workspaces after apps, because workspaces contain apps.
    Workspace.garbageCollectUnusedWorkspaces()
}

@MainActor
private func refreshTabGroups(mapping: [MacApp: [UInt32]]) async throws {
    // First try AXTabGroup-based detection
    var appsWithAxTabGroup: Set<ObjectIdentifier> = []
    for (app, _) in mapping {
        let (hasAxTabGroup, tabGroups) = try await app.getTabGroupWindowIds()
        if hasAxTabGroup {
            appsWithAxTabGroup.insert(ObjectIdentifier(app))
        }
        for windowIds in tabGroups {
            guard let firstWindowId = windowIds.first else { continue }
            if TabGroupTracker.getGroup(for: firstWindowId) != nil { continue }

            let activeWindowId = try await app.getFocusedWindow()?.windowId ?? firstWindowId
            let effectiveActiveId = windowIds.contains(activeWindowId) ? activeWindowId : firstWindowId
            let group = TabGroup(activeWindowId: effectiveActiveId, windowIds: Set(windowIds))
            TabGroupTracker.registerGroup(group)

            for windowId in windowIds where windowId != effectiveActiveId {
                if let window = MacWindow.allWindowsMap[windowId] {
                    window.unbindFromParent()
                    window.bind(to: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                }
            }
        }
    }

    // Then try position-based detection for apps that don't expose AXTabGroup (like Ghostty)
    let mappingWithoutAxTabGroupApps = mapping.filter { !appsWithAxTabGroup.contains(ObjectIdentifier($0.key)) }
    try await detectTabGroupsByPosition(mapping: mappingWithoutAxTabGroupApps)
}

@MainActor
private func detectTabGroupsByPosition(mapping: [MacApp: [UInt32]]) async throws {
    for (app, windowIds) in mapping {
        let positionGroups = try await groupWindowsByPosition(windowIds)

        for (_, groupWindowIds) in positionGroups where groupWindowIds.count > 1 {
            try await processPositionBasedGroup(app: app, windowIds: groupWindowIds)
        }
    }
}

@MainActor
private func groupWindowsByPosition(_ windowIds: [UInt32]) async throws -> [String: [UInt32]] {
    var groups: [String: [UInt32]] = [:]

    for windowId in windowIds {
        guard let window = MacWindow.allWindowsMap[windowId],
              let rect = try? await window.getAxRect() else { continue }

        let key = "\(rect.topLeftCorner.x),\(rect.topLeftCorner.y),\(rect.size.width),\(rect.size.height)"
        groups[key, default: []].append(windowId)
    }

    return groups
}

@MainActor
private func processPositionBasedGroup(app: MacApp, windowIds: [UInt32]) async throws {
    // Check if any window already has a group
    if let existingGroup = windowIds.compactMap({ TabGroupTracker.getGroup(for: $0) }).first {
        // Add new windows to existing group
        for id in windowIds where TabGroupTracker.getGroup(for: id) == nil {
            TabGroupTracker.addWindowToGroup(id, group: existingGroup)
            moveToPopupContainer(windowId: id)
        }
    } else {
        // Create new group
        let focusedId = try await app.getFocusedWindow()?.windowId
        let activeId = windowIds.contains(focusedId ?? 0) ? focusedId! : windowIds[0]

        let group = TabGroup(activeWindowId: activeId, windowIds: Set(windowIds))
        TabGroupTracker.registerGroup(group)

        // Move non-active tabs to popup container
        for id in windowIds where id != activeId {
            moveToPopupContainer(windowId: id)
        }
    }
}

@MainActor
private func moveToPopupContainer(windowId: UInt32) {
    guard let window = MacWindow.allWindowsMap[windowId] else { return }
    window.unbindFromParent()
    window.bind(to: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
}

func refreshObs(_ obs: AXObserver, ax: AXUIElement, notif: CFString, data: UnsafeMutableRawPointer?) {
    let notif = notif as String
    Task { @MainActor in
        if !TrayMenuModel.shared.isEnabled { return }
        scheduleRefreshSession(.ax(notif))
    }
}

func mainWindowChangedObs(_ obs: AXObserver, ax: AXUIElement, notif: CFString, data: UnsafeMutableRawPointer?) {
    let notif = notif as String
    guard let windowId = ax.containingWindowId() else { return }
    Task { @MainActor in
        if !TrayMenuModel.shared.isEnabled { return }
        if let window = MacWindow.allWindowsMap[windowId],
           window.app.isTabDetectionEnabled {
            handleTabSwitch(forWindowId: windowId)
        }
        scheduleRefreshSession(.ax(notif))
    }
}

@MainActor
func handleTabSwitch(forWindowId windowId: UInt32) {
    guard let group = TabGroupTracker.getGroup(for: windowId) else { return }
    let oldActiveWindowId = group.activeWindowId
    if oldActiveWindowId == windowId { return }

    guard let oldWindow = MacWindow.allWindowsMap[oldActiveWindowId] else { return }
    guard let newWindow = MacWindow.allWindowsMap[windowId] else { return }

    guard let oldParent = oldWindow.parent else { return }

    let oldIndex = oldWindow.ownIndex ?? 0
    let oldAdaptiveWeight = (oldParent as? TilingContainer).map { oldWindow.getWeight($0.orientation) } ?? WEIGHT_AUTO

    // Unbind new window first (from popup container), then unbind old window
    // This order matters to avoid index issues
    newWindow.unbindFromParent()
    oldWindow.unbindFromParent()

    // Bind old window to popup container
    oldWindow.bind(to: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)

    // Bind new window to the old position, clamping index to valid range
    let safeIndex = min(oldIndex, oldParent.children.count)
    newWindow.bind(to: oldParent, adaptiveWeight: oldAdaptiveWeight, index: safeIndex)

    group.setActiveWindow(windowId)
}

enum OptimalHideCorner {
    case bottomLeftCorner, bottomRightCorner
}

@MainActor
private func layoutWorkspaces() async throws {
    if !TrayMenuModel.shared.isEnabled {
        for workspace in Workspace.all {
            workspace.allLeafWindowsRecursive.forEach { ($0 as! MacWindow).unhideFromCorner() } // todo as!
            try await workspace.layoutWorkspace() // Unhide tiling windows from corner
        }
        return
    }
    let monitors = monitors
    var monitorToOptimalHideCorner: [CGPoint: OptimalHideCorner] = [:]
    for monitor in monitors {
        let xOff = monitor.width * 0.1
        let yOff = monitor.height * 0.1
        // brc = bottomRightCorner
        let brc1 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: -yOff)
        let brc2 = monitor.rect.bottomRightCorner + CGPoint(x: -xOff, y: 2)
        let brc3 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: 2)

        // blc = bottomLeftCorner
        let blc1 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: -yOff)
        let blc2 = monitor.rect.bottomLeftCorner + CGPoint(x: xOff, y: 2)
        let blc3 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: 2)

        func contains(_ monitor: Monitor, _ point: CGPoint) -> Int { monitor.rect.contains(point) ? 1 : 0 }
        let important = 10

        let corner: OptimalHideCorner =
            monitors.sumOfInt { contains($0, blc1) + contains($0, blc2) + important * contains($0, blc3) } <
            monitors.sumOfInt { contains($0, brc1) + contains($0, brc2) + important * contains($0, brc3) }
            ? .bottomLeftCorner
            : .bottomRightCorner
        monitorToOptimalHideCorner[monitor.rect.topLeftCorner] = corner
    }

    // to reduce flicker, first unhide visible workspaces, then hide invisible ones
    for monitor in monitors {
        let workspace = monitor.activeWorkspace
        workspace.allLeafWindowsRecursive.forEach { ($0 as! MacWindow).unhideFromCorner() } // todo as!
        try await workspace.layoutWorkspace()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        let corner = monitorToOptimalHideCorner[workspace.workspaceMonitor.rect.topLeftCorner] ?? .bottomRightCorner
        for window in workspace.allLeafWindowsRecursive {
            try await (window as! MacWindow).hideInCorner(corner) // todo as!
        }
    }
}

@MainActor
private func normalizeContainers() {
    // Can't do it only for visible workspace because most of the commands support --window-id and --workspace flags
    for workspace in Workspace.all {
        workspace.normalizeContainers()
    }
}

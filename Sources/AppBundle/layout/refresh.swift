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
            await recordDestroyedWindowInfo(window)
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
private func recordDestroyedWindowInfo(_ window: MacWindow) async {
    guard let rect = try? await window.getAxRect() else { return }
    guard let parent = window.parent else { return }

    let parentInfo: DestroyedWindowInfo.ParentInfo?
    switch parent.cases {
        case .tilingContainer, .workspace:
            let index = window.ownIndex ?? 0
            let weight = (parent as? TilingContainer).map { window.getWeight($0.orientation) } ?? WEIGHT_AUTO
            parentInfo = DestroyedWindowInfo.ParentInfo(parent: parent, index: index, adaptiveWeight: weight)
        default:
            parentInfo = nil
    }

    let info = DestroyedWindowInfo(
        windowId: window.windowId,
        appPid: window.app.pid,
        position: rect.topLeftCorner,
        size: rect.size,
        timestamp: Date(),
        parentInfo: parentInfo
    )
    RecentlyDestroyedWindows.record(info)
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
        // Get positions for all windows (including those in groups, for merging)
        var windowPositions: [(windowId: UInt32, position: CGPoint, size: CGSize)] = []
        for windowId in windowIds {
            guard let window = MacWindow.allWindowsMap[windowId] else { continue }
            guard let rect = try? await window.getAxRect() else { continue }
            windowPositions.append((windowId, rect.topLeftCorner, rect.size))
        }

        // Group windows that have the same position
        var processedIds: Set<UInt32> = []
        for i in 0..<windowPositions.count {
            let (windowId, position, size) = windowPositions[i]
            if processedIds.contains(windowId) { continue }

            var groupWindowIds: [UInt32] = [windowId]
            processedIds.insert(windowId)

            for j in (i+1)..<windowPositions.count {
                let (otherId, otherPos, otherSize) = windowPositions[j]
                if processedIds.contains(otherId) { continue }

                if position == otherPos && size == otherSize {
                    groupWindowIds.append(otherId)
                    processedIds.insert(otherId)
                }
            }

            // If we found multiple windows at the same position, they're tabs
            if groupWindowIds.count > 1 {
                // Check if any of these windows is already in a group
                var existingGroup: TabGroup? = nil
                for id in groupWindowIds {
                    if let group = TabGroupTracker.getGroup(for: id) {
                        existingGroup = group
                        break
                    }
                }

                let focusedWindowId = try await app.getFocusedWindow()?.windowId

                if let group = existingGroup {
                    // Merge new windows into the existing group
                    for id in groupWindowIds where TabGroupTracker.getGroup(for: id) == nil {
                        TabGroupTracker.addWindowToGroup(id, group: group)
                        // Move non-active tabs to popup container
                        if id != group.activeWindowId, let window = MacWindow.allWindowsMap[id] {
                            window.unbindFromParent()
                            window.bind(to: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                        }
                    }
                    // Note: Don't call handleTabSwitch here for existing groups.
                    // Tab switches are handled by kAXMainWindowChangedNotification observer.
                    // Calling it here would interfere with tab close promotions in garbageCollect.
                } else {
                    // Create a new group
                    let activeId = groupWindowIds.contains(focusedWindowId ?? 0) ? focusedWindowId! : groupWindowIds[0]

                    let group = TabGroup(activeWindowId: activeId, windowIds: Set(groupWindowIds))
                    TabGroupTracker.registerGroup(group)

                    // Move non-active tabs to popup container
                    for id in groupWindowIds where id != activeId {
                        if let window = MacWindow.allWindowsMap[id] {
                            window.unbindFromParent()
                            window.bind(to: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                        }
                    }
                }
            }
        }
    }
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
            handleTabSwitch(newActiveWindowId: windowId)
        }
        scheduleRefreshSession(.ax(notif))
    }
}

@MainActor
func handleTabSwitch(newActiveWindowId: UInt32) {
    guard let group = TabGroupTracker.getGroup(for: newActiveWindowId) else { return }
    let oldActiveWindowId = group.activeWindowId
    if oldActiveWindowId == newActiveWindowId { return }

    guard let oldWindow = MacWindow.allWindowsMap[oldActiveWindowId] else { return }
    guard let newWindow = MacWindow.allWindowsMap[newActiveWindowId] else { return }

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

    group.setActiveWindow(newActiveWindowId)
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

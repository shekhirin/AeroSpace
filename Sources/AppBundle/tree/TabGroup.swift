import Common
import Foundation

@MainActor
final class TabGroup {
    let id: UUID
    private(set) var windowIds: Set<UInt32>
    private(set) var activeWindowId: UInt32

    init(activeWindowId: UInt32, windowIds: Set<UInt32>) {
        self.id = UUID()
        self.activeWindowId = activeWindowId
        self.windowIds = windowIds
        check(windowIds.contains(activeWindowId))
    }

    func addWindow(_ windowId: UInt32) {
        windowIds.insert(windowId)
    }

    func removeWindow(_ windowId: UInt32) {
        windowIds.remove(windowId)
    }

    func setActiveWindow(_ windowId: UInt32) {
        check(windowIds.contains(windowId))
        activeWindowId = windowId
    }

    var isEmpty: Bool { windowIds.isEmpty }
    var hasMultipleWindows: Bool { windowIds.count > 1 }
}

@MainActor
enum TabGroupTracker {
    private static var windowIdToGroup: [UInt32: TabGroup] = [:]
    private static var groups: [UUID: TabGroup] = [:]

    static func getGroup(for windowId: UInt32) -> TabGroup? {
        windowIdToGroup[windowId]
    }

    static func registerGroup(_ group: TabGroup) {
        groups[group.id] = group
        for windowId in group.windowIds {
            windowIdToGroup[windowId] = group
        }
    }

    static func unregisterWindow(_ windowId: UInt32) {
        guard let group = windowIdToGroup.removeValue(forKey: windowId) else { return }
        group.removeWindow(windowId)
        if group.isEmpty {
            groups.removeValue(forKey: group.id)
        }
    }

    static func unregisterGroup(_ group: TabGroup) {
        for windowId in group.windowIds {
            windowIdToGroup.removeValue(forKey: windowId)
        }
        groups.removeValue(forKey: group.id)
    }

    static func addWindowToGroup(_ windowId: UInt32, group: TabGroup) {
        group.addWindow(windowId)
        windowIdToGroup[windowId] = group
    }
}

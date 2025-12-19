import Common
import Foundation

struct DestroyedWindowInfo {
    let windowId: UInt32
    let appPid: Int32
    let position: CGPoint
    let size: CGSize
    let timestamp: Date
    let parentInfo: ParentInfo?

    struct ParentInfo {
        let parent: any NonLeafTreeNodeObject
        let index: Int
        let adaptiveWeight: CGFloat
    }
}

@MainActor
enum RecentlyDestroyedWindows {
    private static var windows: [DestroyedWindowInfo] = []
    private static let maxAge: TimeInterval = 0.5
    private static let positionTolerance: CGFloat = 5.0
    private static let sizeTolerance: CGFloat = 5.0

    static func record(_ info: DestroyedWindowInfo) {
        cleanup()
        windows.append(info)
    }

    static func findMatch(appPid: Int32, position: CGPoint, size: CGSize) -> DestroyedWindowInfo? {
        cleanup()
        return windows.first { info in
            info.appPid == appPid &&
            abs(info.position.x - position.x) <= positionTolerance &&
            abs(info.position.y - position.y) <= positionTolerance &&
            abs(info.size.width - size.width) <= sizeTolerance &&
            abs(info.size.height - size.height) <= sizeTolerance
        }
    }

    static func remove(windowId: UInt32) {
        windows.removeAll { $0.windowId == windowId }
    }

    private static func cleanup() {
        let now = Date()
        windows.removeAll { now.timeIntervalSince($0.timestamp) > maxAge }
    }
}

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

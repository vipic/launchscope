import Foundation

struct StartupItemStateSnapshot: Codable, Equatable, Sendable {
    var isEnabled: Bool?
    var runtimeState: RuntimeState?

    init(item: StartupItem?) {
        isEnabled = item?.isEnabled
        runtimeState = item?.runtime.state
    }
}

struct ControlHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var itemID: String
    var label: String
    var displayName: String
    var source: StartupSource
    var action: StartupItemControlAction
    var outcome: StartupItemControlOutcome
    var message: String
    var before: StartupItemStateSnapshot
    var after: StartupItemStateSnapshot
    var reversesEntryID: UUID?
    var reversedAt: Date?
    var reversedByEntryID: UUID?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        item: StartupItem,
        afterItem: StartupItem?,
        action: StartupItemControlAction,
        result: StartupItemControlResult,
        reversesEntryID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        itemID = item.controlHistoryKey
        label = item.label
        displayName = item.displayName
        source = item.source
        self.action = action
        outcome = result.outcome
        message = result.title
        before = StartupItemStateSnapshot(item: item)
        after = StartupItemStateSnapshot(item: afterItem)
        self.reversesEntryID = reversesEntryID
    }

    var inverseAction: StartupItemControlAction? {
        outcome == .failure || reversedAt != nil ? nil : action.inverse
    }
}

extension StartupItem {
    var controlHistoryKey: String {
        privacySafeKey
    }
}

enum ControlHistoryPolicy {
    static func canUndo(
        _ entry: ControlHistoryEntry,
        in entries: [ControlHistoryEntry],
        currentAction: StartupItemControlAction?
    ) -> Bool {
        guard let inverse = entry.inverseAction,
              currentAction == inverse,
              let latestActive = entries.first(where: {
                  $0.itemID == entry.itemID && $0.outcome != .failure && $0.reversedAt == nil
              }) else { return false }
        return latestActive.id == entry.id
    }
}

import XCTest
@testable import LaunchScope

final class AuditTimelineTests: XCTestCase {
    func testBuildsFirstSeenRemovedChangedAndControlEvents() {
        let firstItem = item(id: "first", state: .running)
        let removedItem = item(id: "removed", state: .running)
        let first = snapshot([firstItem, removedItem], time: 100)
        var changedItem = firstItem
        changedItem.runtime.state = .disabled
        changedItem.isEnabled = false
        let addedItem = item(id: "added", state: .running)
        let second = snapshot([changedItem, addedItem], time: 200)
        let control = ControlHistoryEntry(
            timestamp: Date(timeIntervalSince1970: 150), item: firstItem, afterItem: changedItem,
            action: .disable, result: StartupItemControlResult(outcome: .success, title: "已停用", message: "完成")
        )

        let events = AuditTimeline.build(snapshots: [first, second], controlHistory: [control])
        XCTAssertEqual(events.count { $0.kind == .firstSeen }, 3)
        XCTAssertEqual(events.count { $0.kind == .removed }, 1)
        XCTAssertEqual(events.count { $0.kind == .changed }, 1)
        XCTAssertEqual(events.count { $0.kind == .control }, 1)
        XCTAssertEqual(events.first?.timestamp, Date(timeIntervalSince1970: 200))
    }

    private func item(id: String, state: RuntimeState) -> StartupItem {
        StartupItem(
            id: id, label: "com.example.\(id)", source: .userLaunchAgent,
            runtime: RuntimeInfo(state: state), targetExists: true, isEnabled: true
        )
    }

    private func snapshot(_ items: [StartupItem], time: TimeInterval) -> ScanSnapshot {
        ScanSnapshot(report: ScanReport(
            items: items, issues: [], scannedAt: Date(timeIntervalSince1970: time),
            duration: 0, backgroundTasksUpdatedAt: nil
        ))
    }
}

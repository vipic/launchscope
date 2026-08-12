import Foundation
import XCTest
@testable import LaunchScope

@MainActor
final class DashboardFocusTests: XCTestCase {
    func testSelectingFilterRequestsListFocusWithoutSearchStealingIt() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DashboardStore(
            historyPersistence: ControlHistoryPersistence(fileURL: directory.appendingPathComponent("history.json")),
            snapshotPersistence: ScanSnapshotPersistence(fileURL: directory.appendingPathComponent("snapshots.json")),
            annotationPersistence: ItemAnnotationPersistence(fileURL: directory.appendingPathComponent("annotations.json")),
            notificationLedgerPersistence: NotificationLedgerPersistence(fileURL: directory.appendingPathComponent("notifications.json")),
            notifier: FocusTestNotifier()
        )
        store.selectedItemID = "previous-selection"
        store.searchText = "keep-search-focus"
        let initialRequest = store.listFocusRequest

        store.selectFilter(.all)

        XCTAssertEqual(store.selectedFilter, .all)
        XCTAssertNil(store.selectedItemID)
        XCTAssertEqual(store.listFocusRequest, initialRequest + 1)
        XCTAssertEqual(store.searchText, "keep-search-focus")

        store.searchText = "updated-query"
        XCTAssertEqual(store.listFocusRequest, initialRequest + 1)
    }
}

@MainActor
private struct FocusTestNotifier: NewItemNotifying {
    func requestAuthorization() async throws -> Bool { true }
    func notify(newItems: [ScanSnapshotItem]) async throws {}
}

import XCTest
@testable import LaunchScope

final class ScanSnapshotTests: XCTestCase {
    func testDiffFindsAddedRemovedAndChangedItems() {
        let unchanged = makeItem(id: "unchanged", label: "com.example.unchanged")
        let removed = makeItem(id: "removed", label: "com.example.removed")
        let previous = snapshot(items: [unchanged, removed], time: 100)

        var changed = unchanged
        changed.isEnabled = false
        changed.runtime.state = .disabled
        let added = makeItem(id: "added", label: "com.example.added")
        let current = snapshot(items: [changed, added], time: 200)

        let changes = ScanSnapshotDiff.compare(previous: previous, current: current)

        XCTAssertEqual(changes.count { $0.kind == .added }, 1)
        XCTAssertEqual(changes.count { $0.kind == .removed }, 1)
        XCTAssertEqual(changes.count { $0.kind == .changed }, 1)
        XCTAssertEqual(
            changes.first { $0.kind == .changed }?.changedFields,
            ["允许状态", "运行状态"]
        )
    }

    func testUnchangedSnapshotProducesNoDiff() {
        let item = makeItem(id: "same", label: "com.example.same")
        let previous = snapshot(items: [item], time: 100)
        let current = snapshot(items: [item], time: 200)

        XCTAssertTrue(ScanSnapshotDiff.compare(previous: previous, current: current).isEmpty)
    }

    func testSnapshotPersistenceOmitsPathsCommandsAndSecrets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchscope-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let cron = StartupItem(
            id: "cron:0:/private/SECRET_PATH",
            label: "cron.1",
            displayName: "curl --token SECRET_TOKEN https://example.com",
            source: .cron,
            sourcePath: "/private/SECRET_PATH",
            arguments: ["--token", "SECRET_TOKEN"],
            environment: ["API_TOKEN": "SECRET_TOKEN"]
        )
        let snapshot = snapshot(items: [cron], time: 100)
        let persistence = ScanSnapshotPersistence(fileURL: fileURL)
        try persistence.save(snapshot)

        XCTAssertEqual(try persistence.load(), snapshot)
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("SECRET_PATH"))
        XCTAssertFalse(text.contains("SECRET_TOKEN"))
        XCTAssertFalse(text.contains("curl"))
        XCTAssertTrue(text.contains("Cron 任务"))
    }

    private func snapshot(items: [StartupItem], time: TimeInterval) -> ScanSnapshot {
        ScanSnapshot(report: ScanReport(
            items: items,
            issues: [],
            scannedAt: Date(timeIntervalSince1970: time),
            duration: 0,
            backgroundTasksUpdatedAt: nil
        ))
    }

    private func makeItem(id: String, label: String) -> StartupItem {
        StartupItem(
            id: id,
            label: label,
            source: .userLaunchAgent,
            runtime: RuntimeInfo(state: .running, domain: "gui/501"),
            targetExists: true,
            isEnabled: true
        )
    }
}

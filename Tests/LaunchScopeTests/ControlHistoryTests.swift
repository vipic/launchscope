import XCTest
@testable import LaunchScope

final class ControlHistoryTests: XCTestCase {
    func testActionInversePairs() {
        XCTAssertEqual(StartupItemControlAction.disable.inverse, .enable)
        XCTAssertEqual(StartupItemControlAction.enable.inverse, .disable)
        XCTAssertEqual(StartupItemControlAction.stopHomebrew.inverse, .startHomebrew)
        XCTAssertEqual(StartupItemControlAction.startHomebrew.inverse, .stopHomebrew)
        XCTAssertEqual(StartupItemControlAction.disableCron.inverse, .enableCron)
        XCTAssertEqual(StartupItemControlAction.enableCron.inverse, .disableCron)
        XCTAssertEqual(StartupItemControlAction.disableShellLine.inverse, .enableShellLine)
        XCTAssertEqual(StartupItemControlAction.enableShellLine.inverse, .disableShellLine)
    }

    func testRecoveryActionClassification() {
        XCTAssertTrue(StartupItemControlAction.enable.isRecoveryAction)
        XCTAssertTrue(StartupItemControlAction.enableCron.isRecoveryAction)
        XCTAssertTrue(StartupItemControlAction.enableShellLine.isRecoveryAction)
        XCTAssertTrue(StartupItemControlAction.startHomebrew.isRecoveryAction)
        XCTAssertFalse(StartupItemControlAction.disable.isRecoveryAction)
        XCTAssertFalse(StartupItemControlAction.stopHomebrew.isRecoveryAction)
    }

    func testFailedEntryCannotBeUndone() {
        let entry = makeEntry(outcome: .failure)
        XCTAssertNil(entry.inverseAction)
    }

    func testReversedEntryCannotBeUndoneAgain() {
        var entry = makeEntry(outcome: .success)
        entry.reversedAt = Date()
        XCTAssertNil(entry.inverseAction)
    }

    func testPersistenceRoundTripOmitsSensitiveItemFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchscope-history-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = ControlHistoryPersistence(fileURL: fileURL)
        let entry = makeEntry(outcome: .success)
        try persistence.save([entry])

        XCTAssertEqual(try persistence.load(), [entry])
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("SECRET_TOKEN"))
        XCTAssertFalse(text.contains("/private/example.plist"))
        XCTAssertFalse(text.contains("--password"))
    }

    func testUndoRequiresLatestActiveEntryAndMatchingCurrentAction() {
        let older = makeEntry(outcome: .success)
        var latest = makeEntry(outcome: .success)
        latest.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        latest.action = .enable
        let entries = [latest, older]

        XCTAssertFalse(ControlHistoryPolicy.canUndo(older, in: entries, currentAction: .enable))
        XCTAssertTrue(ControlHistoryPolicy.canUndo(latest, in: entries, currentAction: .disable))
        XCTAssertFalse(ControlHistoryPolicy.canUndo(latest, in: entries, currentAction: .enable))
    }

    private func makeEntry(outcome: StartupItemControlOutcome) -> ControlHistoryEntry {
        let item = StartupItem(
            id: "agent",
            label: "com.example.agent",
            displayName: "Example Agent",
            source: .userLaunchAgent,
            sourcePath: "/private/example.plist",
            arguments: ["--password", "SECRET_TOKEN"],
            environment: ["API_TOKEN": "SECRET_TOKEN"],
            runtime: RuntimeInfo(state: .running, domain: "gui/501"),
            isEnabled: true
        )
        var after = item
        after.runtime.state = .disabled
        after.isEnabled = false
        let result = StartupItemControlResult(
            outcome: outcome,
            title: "测试结果",
            message: "SECRET_TOKEN /private/example.plist --password"
        )
        return ControlHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            item: item,
            afterItem: after,
            action: .disable,
            result: result
        )
    }
}

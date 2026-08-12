import Foundation
import XCTest
@testable import LaunchScope

final class AuditAndAnnotationTests: XCTestCase {
    func testJSONExportOmitsSensitiveStartupFieldsByDefault() throws {
        let item = StartupItem(
            id: "/Users/me/Library/LaunchAgents/secret.plist",
            label: "com.example.agent",
            source: .userLaunchAgent,
            sourcePath: "/Users/me/Library/LaunchAgents/secret.plist",
            executablePath: "/private/tool",
            arguments: ["--token", "top-secret"],
            environment: ["PASSWORD": "top-secret"],
            configuration: ["Raw": "top-secret"]
        )
        let annotation = ItemAnnotation(
            itemKey: item.privacySafeKey,
            note: "private-note",
            tags: ["检查"],
            isTrusted: true,
            updatedAt: Date()
        )

        let data = try AuditExporter.data(
            format: .json,
            items: [item],
            annotations: [annotation.itemKey: annotation],
            issues: [ScanIssue(source: "/private/path", message: "top-secret", severity: .warning)],
            changes: [],
            scannedAt: Date(),
            options: AuditExportOptions()
        )
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.contains("com.example.agent"))
        XCTAssertTrue(text.contains("检查"))
        XCTAssertFalse(text.contains("/Users/me"))
        XCTAssertFalse(text.contains("top-secret"))
        XCTAssertFalse(text.contains("private-note"))
    }

    func testAnnotationPersistenceRoundTripUsesPrivacySafeKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ItemAnnotationPersistence(fileURL: directory.appendingPathComponent("annotations.json"))
        let value = ItemAnnotation(
            itemKey: "userLaunchAgent:com.example.agent",
            note: "稍后检查",
            tags: ["工作"],
            isTrusted: true,
            updatedAt: Date(timeIntervalSince1970: 123)
        )

        try persistence.save([value])
        XCTAssertEqual(try persistence.load(), [value])
        let raw = try String(contentsOf: persistence.fileURL, encoding: .utf8)
        XCTAssertFalse(raw.contains("LaunchAgents/"))
    }

    func testNotificationLedgerRoundTripStoresOnlyChangeIDs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = NotificationLedgerPersistence(fileURL: directory.appendingPathComponent("ledger.json"))
        let ledger = NotificationLedger(activeChangeIDs: ["added:abc"])
        try persistence.save(ledger)
        XCTAssertEqual(try persistence.load(), ledger)
    }
}

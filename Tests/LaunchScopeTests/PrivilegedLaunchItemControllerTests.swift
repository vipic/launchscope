import CryptoKit
import Foundation
import XCTest
import LaunchScopePrivilegedCore
@testable import LaunchScope

final class PrivilegedLaunchItemControllerTests: XCTestCase {
    func testGlobalAgentUsesFixedLaunchctlArguments() throws {
        let fixture = try makeFixture()
        let runner = PrivilegedRecordingRunner(results: [
            .init(output: "", error: "", exitCode: 0),
            .init(output: "", error: "", exitCode: 0),
        ])
        let controller = PrivilegedLaunchItemController(
            runner: runner,
            policy: .init(allowedDirectory: fixture.directory.path, requiredOwner: getuid(), appleSignatureChecker: { _ in false })
        )
        let result = controller.setGlobalAgentEnabled(
            path: fixture.file.path, label: fixture.label, expectedSHA256: fixture.hash,
            enabled: false, userIdentifier: 501
        )
        XCTAssertEqual(result.outcome, "success")
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["disable", "gui/501/com.example.global"],
            ["bootout", "gui/501", fixture.file.path],
        ])
    }

    func testPolicyRejectsChangedFileBeforeCallingLaunchctl() throws {
        let fixture = try makeFixture()
        let runner = PrivilegedRecordingRunner(results: [])
        let controller = PrivilegedLaunchItemController(
            runner: runner,
            policy: .init(allowedDirectory: fixture.directory.path, requiredOwner: getuid(), appleSignatureChecker: { _ in false })
        )
        try Data("changed".utf8).write(to: fixture.file)
        let result = controller.setGlobalAgentEnabled(
            path: fixture.file.path, label: fixture.label, expectedSHA256: fixture.hash,
            enabled: false, userIdentifier: 501
        )
        XCTAssertEqual(result.outcome, "failure")
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(result.message.contains("变化"))
    }

    func testPolicyRejectsAppleSignedExecutableAndUnsafeLabel() throws {
        let fixture = try makeFixture()
        let applePolicy = PrivilegedLaunchItemPolicy(
            allowedDirectory: fixture.directory.path, requiredOwner: getuid(), appleSignatureChecker: { _ in true }
        )
        XCTAssertThrowsError(try applePolicy.validate(
            path: fixture.file.path, label: fixture.label, expectedSHA256: fixture.hash
        ))
        XCTAssertThrowsError(try applePolicy.validate(
            path: fixture.file.path, label: "../unsafe", expectedSHA256: fixture.hash
        ))
    }

    func testDaemonUsesSystemDomainAndFixedArguments() throws {
        let fixture = try makeFixture()
        let runner = PrivilegedRecordingRunner(results: [
            .init(output: "", error: "", exitCode: 0),
            .init(output: "", error: "", exitCode: 0),
        ])
        let daemonPolicy = PrivilegedLaunchItemPolicy(
            allowedDirectory: fixture.directory.path, requiredOwner: getuid(), appleSignatureChecker: { _ in false }
        )
        let controller = PrivilegedLaunchItemController(runner: runner, daemonPolicy: daemonPolicy)
        let result = controller.setDaemonEnabled(
            path: fixture.file.path, label: fixture.label, expectedSHA256: fixture.hash, enabled: false
        )
        XCTAssertEqual(result.outcome, "success")
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["disable", "system/com.example.global"],
            ["bootout", "system", fixture.file.path],
        ])
    }

    func testDaemonStopsAfterOverrideTimeout() throws {
        let fixture = try makeFixture()
        let runner = PrivilegedRecordingRunner(results: [
            .init(output: "", error: "", exitCode: 124, timedOut: true),
        ])
        let daemonPolicy = PrivilegedLaunchItemPolicy(
            allowedDirectory: fixture.directory.path, requiredOwner: getuid(), appleSignatureChecker: { _ in false }
        )
        let controller = PrivilegedLaunchItemController(runner: runner, daemonPolicy: daemonPolicy)
        let result = controller.setDaemonEnabled(
            path: fixture.file.path, label: fixture.label, expectedSHA256: fixture.hash, enabled: false
        )
        XCTAssertEqual(result.outcome, "failure")
        XCTAssertTrue(result.message.contains("超时"))
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testDaemonReportsPartialResultWhenRuntimeUpdateFails() throws {
        let fixture = try makeFixture()
        let runner = PrivilegedRecordingRunner(results: [
            .init(output: "", error: "", exitCode: 0),
            .init(output: "", error: "service is busy", exitCode: 5),
        ])
        let daemonPolicy = PrivilegedLaunchItemPolicy(
            allowedDirectory: fixture.directory.path, requiredOwner: getuid(), appleSignatureChecker: { _ in false }
        )
        let controller = PrivilegedLaunchItemController(runner: runner, daemonPolicy: daemonPolicy)
        let result = controller.setDaemonEnabled(
            path: fixture.file.path, label: fixture.label, expectedSHA256: fixture.hash, enabled: true
        )
        XCTAssertEqual(result.outcome, "partial")
        XCTAssertTrue(result.message.contains("service is busy"))
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["enable", "system/com.example.global"],
            ["bootstrap", "system", fixture.file.path],
        ])
    }

    func testPolicyRejectsSymlinkAndWrongOwner() throws {
        let fixture = try makeFixture()
        let link = fixture.directory.appendingPathComponent("linked.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.file)
        let safePolicy = PrivilegedLaunchItemPolicy(
            allowedDirectory: fixture.directory.path, requiredOwner: getuid(), appleSignatureChecker: { _ in false }
        )
        XCTAssertThrowsError(try safePolicy.validate(path: link.path, label: fixture.label, expectedSHA256: fixture.hash))
        let wrongOwner = PrivilegedLaunchItemPolicy(
            allowedDirectory: fixture.directory.path, requiredOwner: getuid() + 1, appleSignatureChecker: { _ in false }
        )
        XCTAssertThrowsError(try wrongOwner.validate(path: fixture.file.path, label: fixture.label, expectedSHA256: fixture.hash))
    }

    func testPolicyRejectsFileOutsideExactAllowedDirectory() throws {
        let fixture = try makeFixture()
        let otherDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
        let outsideFile = otherDirectory.appendingPathComponent("outside.plist")
        try FileManager.default.copyItem(at: fixture.file, to: outsideFile)
        addTeardownBlock { try? FileManager.default.removeItem(at: otherDirectory) }
        let policy = PrivilegedLaunchItemPolicy(
            allowedDirectory: fixture.directory.path, requiredOwner: getuid(), appleSignatureChecker: { _ in false }
        )
        XCTAssertThrowsError(
            try policy.validate(path: outsideFile.path, label: fixture.label, expectedSHA256: fixture.hash)
        )
    }

    private func makeFixture() throws -> (directory: URL, file: URL, label: String, hash: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let label = "com.example.global"
        let file = directory.appendingPathComponent("global.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["Label": label, "Program": "/opt/example/bin/agent"],
            format: .xml, options: 0
        )
        try data.write(to: file)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (directory, file, label, hash)
    }
}

private final class PrivilegedRecordingRunner: PrivilegedCommandRunning, @unchecked Sendable {
    struct Call { var executable: String; var arguments: [String] }
    private(set) var calls: [Call] = []
    private var results: [PrivilegedCommandResult]
    init(results: [PrivilegedCommandResult]) { self.results = results }
    func run(executable: String, arguments: [String], timeout: TimeInterval) -> PrivilegedCommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return results.removeFirst()
    }
}

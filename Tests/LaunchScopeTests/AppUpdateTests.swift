import Foundation
import XCTest
@testable import LaunchScope

final class AppUpdateTests: XCTestCase {
    func testSemanticVersionComparisonIgnoresPrefixAndPrereleaseSuffix() throws {
        let installed = try XCTUnwrap(AppVersion("0.1.9-dev"))
        let latest = try XCTUnwrap(AppVersion("v0.2.0"))

        XCTAssertLessThan(installed, latest)
        XCTAssertEqual(AppVersion("v1.2.3"), AppVersion("1.2.3"))
        XCTAssertNil(AppVersion("1.2"))
        XCTAssertNil(AppVersion("latest"))
    }

    func testGitHubReleaseDecoderAcceptsOfficialReleasePage() throws {
        let data = Data(#"{"tag_name":"v0.2.0","name":"安全更新","html_url":"https://github.com/vipic/launchscope/releases/tag/v0.2.0","assets":[{"name":"LaunchScope-0.2.0.dmg","browser_download_url":"https://github.com/vipic/launchscope/releases/download/v0.2.0/LaunchScope-0.2.0.dmg","size":3456789},{"name":"LaunchScope-0.2.0.dmg.sha256","browser_download_url":"https://github.com/vipic/launchscope/releases/download/v0.2.0/LaunchScope-0.2.0.dmg.sha256","size":135}]}"#.utf8)

        let release = try GitHubAppUpdateChecker.decodeRelease(from: data)

        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.title, "安全更新")
        XCTAssertEqual(release.pageURL.host, "github.com")
        XCTAssertEqual(release.downloadURL.pathExtension, "dmg")
        XCTAssertEqual(release.downloadSize, 3_456_789)
        XCTAssertEqual(release.checksumURL?.pathExtension, "sha256")
    }

    func testGitHubReleaseDecoderRejectsUntrustedDownloadPage() {
        let data = Data(#"{"tag_name":"0.2.0","name":null,"html_url":"https://example.com/download"}"#.utf8)

        XCTAssertThrowsError(try GitHubAppUpdateChecker.decodeRelease(from: data)) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidRelease)
        }
    }

    func testGitHubReleaseDecoderRequiresChecksumAsset() {
        let data = Data(#"{"tag_name":"0.2.0","name":"LaunchScope 0.2.0","html_url":"https://github.com/vipic/launchscope/releases/tag/0.2.0","assets":[{"name":"LaunchScope-0.2.0.dmg","browser_download_url":"https://github.com/vipic/launchscope/releases/download/0.2.0/LaunchScope-0.2.0.dmg","size":1000}]}"#.utf8)

        XCTAssertThrowsError(try GitHubAppUpdateChecker.decodeRelease(from: data)) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidRelease)
        }
    }

    func testDownloadProgressUsesResponseLengthAndAssetFallback() throws {
        XCTAssertEqual(
            try XCTUnwrap(AppUpdater.downloadProgress(totalBytesWritten: 250, totalBytesExpected: 1_000, expectedSize: 2_000)),
            0.25,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(AppUpdater.downloadProgress(totalBytesWritten: 250, totalBytesExpected: -1, expectedSize: 1_000)),
            0.25,
            accuracy: 0.001
        )
    }

    func testInstallerWaitsForExitAndKeepsRollbackPath() throws {
        let script = AppUpdater.installScript(
            dmg: "/tmp/LaunchScope.dmg",
            staging: "/tmp/launchscope-update-test",
            target: "/Applications/LaunchScope.app",
            pid: 123,
            expectedVersion: "0.5.1"
        )

        let waitRange = try XCTUnwrap(script.range(of: "while kill -0 \"$CURRENT_PID\""))
        let replaceRange = try XCTUnwrap(script.range(of: "mv \"$TARGET\" \"$BACKUP\""))
        XCTAssertLessThan(waitRange.lowerBound, replaceRange.lowerBound)
        XCTAssertTrue(script.contains("EXPECTED_VERSION='0.5.1'"))
        XCTAssertTrue(script.contains("mv \"$BACKUP\" \"$TARGET\""))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict \"$TARGET\""))
    }

    func testInstallerIsLaunchedDetachedBeforeTheAppTerminates() {
        let command = AppUpdater.detachedLaunchCommand(
            scriptURL: URL(fileURLWithPath: "/tmp/launchscope update/install.sh")
        )

        XCTAssertTrue(command.hasPrefix("nohup /bin/sh "))
        XCTAssertTrue(command.contains("'/tmp/launchscope update/install.sh'"))
        XCTAssertTrue(command.contains("2>&1 </dev/null"))
        XCTAssertTrue(command.hasSuffix("&"))
    }

    func testPublishedReleaseDownloadsWithProgressAndChecksum() async throws {
        guard ProcessInfo.processInfo.environment["LAUNCHSCOPE_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("设置 LAUNCHSCOPE_NETWORK_TESTS=1 运行真实更新下载测试")
        }
        let release = try await GitHubAppUpdateChecker().latestRelease()
        let recorder = UpdateProgressRecorder()
        let update = try await AppUpdater().download(release: release) { progress in
            recorder.append(progress)
        }
        defer { try? FileManager.default.removeItem(at: update.stagingURL) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: update.dmgURL.path))
        XCTAssertEqual(recorder.values.last, 1)
        XCTAssertTrue(recorder.values.allSatisfy { (0...1).contains($0) })

        let runner = CommandRunner()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchscope-update-integration-\(UUID().uuidString)", isDirectory: true)
        let seedMount = root.appendingPathComponent("seed-mount", isDirectory: true)
        let installerStaging = root.appendingPathComponent("installer", isDirectory: true)
        let target = root.appendingPathComponent("LaunchScope.app", isDirectory: true)
        try FileManager.default.createDirectory(at: seedMount, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: installerStaging, withIntermediateDirectories: true)
        defer {
            _ = runner.run(executable: "/usr/bin/hdiutil", arguments: ["detach", seedMount.path, "-force"], timeout: 10)
            try? FileManager.default.removeItem(at: root)
        }

        let attach = runner.run(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", update.dmgURL.path, "-nobrowse", "-readonly", "-mountpoint", seedMount.path],
            timeout: 30
        )
        XCTAssertEqual(attach.exitCode, 0, attach.standardError)
        let seed = runner.run(
            executable: "/usr/bin/ditto",
            arguments: [seedMount.appendingPathComponent("LaunchScope.app").path, target.path],
            timeout: 30
        )
        XCTAssertEqual(seed.exitCode, 0, seed.standardError)
        let detach = runner.run(
            executable: "/usr/bin/hdiutil",
            arguments: ["detach", seedMount.path],
            timeout: 15
        )
        XCTAssertEqual(detach.exitCode, 0, detach.standardError)

        let marker = target.appendingPathComponent("update-test-marker")
        try Data("old-copy".utf8).write(to: marker)
        let installerDMG = installerStaging.appendingPathComponent("LaunchScope.dmg")
        try FileManager.default.copyItem(at: update.dmgURL, to: installerDMG)
        let scriptURL = installerStaging.appendingPathComponent("install.sh")
        let script = AppUpdater.installScript(
            dmg: installerDMG.path,
            staging: installerStaging.path,
            target: target.path,
            pid: Int32.max,
            expectedVersion: release.version,
            relaunch: false
        )
        try Data(script.utf8).write(to: scriptURL)
        let install = runner.run(executable: "/bin/sh", arguments: [scriptURL.path], timeout: 60)

        XCTAssertEqual(install.exitCode, 0, install.standardError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertEqual(
            Bundle(url: target)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            release.version
        )
    }
}

@MainActor
final class AppUpdateStoreTests: XCTestCase {
    func testManualCheckReportsAvailableVersionAndPersistsCheckDate() async throws {
        let suiteName = "AppUpdateStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let release = AppRelease(
            version: "0.2.0",
            title: "LaunchScope 0.2.0",
            pageURL: URL(string: "https://github.com/vipic/launchscope/releases/tag/0.2.0")!
        )
        let store = AppUpdateStore(
            checker: StubUpdateChecker(release: release),
            defaults: defaults,
            now: { checkedAt },
            currentVersion: "0.1.1",
            currentBuild: "10"
        )

        store.checkForUpdates()
        for _ in 0..<20 where store.state == .checking {
            await Task.yield()
        }

        XCTAssertEqual(store.state, .updateAvailable(release))
        XCTAssertEqual(store.lastCheckedAt, checkedAt)
        XCTAssertEqual(defaults.object(forKey: PreferenceKeys.lastUpdateCheckAt) as? Date, checkedAt)
    }

    func testRecentAutomaticCheckIsThrottled() throws {
        let suiteName = "AppUpdateStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defaults.set(now.addingTimeInterval(-60), forKey: PreferenceKeys.lastUpdateCheckAt)
        let store = AppUpdateStore(
            checker: StubUpdateChecker(release: nil),
            defaults: defaults,
            now: { now },
            currentVersion: "0.1.1"
        )

        store.checkAutomaticallyIfNeeded()

        XCTAssertEqual(store.state, .idle)
    }

    func testFailedCheckDoesNotDelayTheNextAutomaticRetry() async throws {
        let suiteName = "AppUpdateStoreRetryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppUpdateStore(
            checker: StubUpdateChecker(release: nil),
            defaults: defaults,
            currentVersion: "0.5.0",
            previousUpdateFailure: nil,
            terminate: {}
        )

        store.checkForUpdates()
        for _ in 0..<30 where store.state == .checking { await Task.yield() }

        XCTAssertNil(store.lastCheckedAt)
        XCTAssertNil(defaults.object(forKey: PreferenceKeys.lastUpdateCheckAt))
        guard case .failed = store.state else {
            return XCTFail("手动检查失败应进入明确失败状态")
        }
    }

    func testInstallHandoffDownloadsThenTerminatesForDetachedInstaller() async throws {
        let suiteName = "AppUpdateStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let release = AppRelease(
            version: "0.5.1",
            title: "LaunchScope 0.5.1",
            pageURL: URL(string: "https://github.com/vipic/launchscope/releases/tag/0.5.1")!
        )
        let recorder = TerminationRecorder()
        let store = AppUpdateStore(
            checker: StubUpdateChecker(release: release),
            updater: StubAppUpdater(release: release),
            defaults: defaults,
            currentVersion: "0.5.0",
            previousUpdateFailure: nil,
            terminate: { recorder.didTerminate = true }
        )
        store.checkForUpdates()
        for _ in 0..<30 where store.state == .checking { await Task.yield() }

        store.installUpdate(release)
        for _ in 0..<50 where !recorder.didTerminate { await Task.yield() }

        XCTAssertTrue(recorder.didTerminate)
        XCTAssertEqual(store.state, .installing(release))
    }

    func testPreviousInstallerFailureIsShownOnNextLaunch() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AppUpdateStoreFailureTests.\(UUID().uuidString)"))
        let store = AppUpdateStore(
            checker: StubUpdateChecker(release: nil),
            defaults: defaults,
            currentVersion: "0.5.0",
            previousUpdateFailure: "复制失败",
            terminate: {}
        )

        XCTAssertEqual(store.state, .failed("上次自动更新未能完成：复制失败"))
    }
}

private struct StubUpdateChecker: AppUpdateChecking {
    let release: AppRelease?

    func latestRelease() async throws -> AppRelease {
        guard let release else { throw AppUpdateError.invalidResponse }
        return release
    }
}

private struct StubAppUpdater: AppUpdating {
    let release: AppRelease

    func download(
        release: AppRelease,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> DownloadedAppUpdate {
        onProgress(0.5)
        onProgress(1)
        return DownloadedAppUpdate(
            release: release,
            stagingURL: FileManager.default.temporaryDirectory.appendingPathComponent("launchscope-update-test"),
            dmgURL: FileManager.default.temporaryDirectory.appendingPathComponent("LaunchScope-test.dmg")
        )
    }

    func prepareAndLaunchInstaller(
        update: DownloadedAppUpdate,
        currentBundleURL: URL,
        currentPID: Int32
    ) async throws {}
}

@MainActor
private final class TerminationRecorder {
    var didTerminate = false
}

private final class UpdateProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    func append(_ value: Double) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

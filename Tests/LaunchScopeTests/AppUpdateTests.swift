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
        let data = Data(#"{"tag_name":"v0.2.0","name":"安全更新","html_url":"https://github.com/vipic/launchscope/releases/tag/v0.2.0"}"#.utf8)

        let release = try GitHubAppUpdateChecker.decodeRelease(from: data)

        XCTAssertEqual(release.version, "0.2.0")
        XCTAssertEqual(release.title, "安全更新")
        XCTAssertEqual(release.pageURL.host, "github.com")
    }

    func testGitHubReleaseDecoderRejectsUntrustedDownloadPage() {
        let data = Data(#"{"tag_name":"0.2.0","name":null,"html_url":"https://example.com/download"}"#.utf8)

        XCTAssertThrowsError(try GitHubAppUpdateChecker.decodeRelease(from: data)) { error in
            XCTAssertEqual(error as? AppUpdateError, .invalidRelease)
        }
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
}

private struct StubUpdateChecker: AppUpdateChecking {
    let release: AppRelease?

    func latestRelease() async throws -> AppRelease {
        guard let release else { throw AppUpdateError.invalidResponse }
        return release
    }
}

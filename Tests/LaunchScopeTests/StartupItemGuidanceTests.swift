import XCTest
@testable import LaunchScope

final class StartupItemGuidanceTests: XCTestCase {
    func testLoginItemOpensSystemSettingsWithoutCommand() {
        let item = StartupItem(id: "login", label: "com.example.login", source: .loginItem)

        XCTAssertTrue(item.guidance.opensLoginItemSettings)
        XCTAssertNil(item.guidance.diagnosticCommand)
    }

    func testHomebrewCommandQuotesServiceName() {
        let item = StartupItem(
            id: "brew",
            label: "homebrew.mxcl.example",
            displayName: "example's service",
            source: .homebrewService
        )

        XCTAssertEqual(
            item.guidance.diagnosticCommand,
            "brew services info 'example'\\''s service'"
        )
    }

    func testLaunchdCommandIncludesDomainAndLabel() {
        let item = StartupItem(
            id: "agent",
            label: "com.example.agent",
            source: .userLaunchAgent,
            runtime: RuntimeInfo(domain: "gui/501")
        )

        XCTAssertEqual(
            item.guidance.diagnosticCommand,
            "/bin/launchctl print 'gui/501/com.example.agent'"
        )
    }

    func testAppleItemNeverOffersManagementGuidance() {
        let item = StartupItem(
            id: "apple",
            label: "com.apple.example",
            source: .systemLaunchDaemon,
            isAppleItem: true
        )

        XCTAssertEqual(item.guidance.title, "仅建议查看")
        XCTAssertFalse(item.guidance.opensLoginItemSettings)
    }

    func testPseudoSourcePathIsNotRevealable() {
        let item = StartupItem(
            id: "cron",
            label: "cron.1",
            source: .cron,
            sourcePath: "当前用户 crontab"
        )

        XCTAssertNil(item.revealableSourcePath)
        XCTAssertEqual(item.guidance.diagnosticCommand, "/usr/bin/crontab -l")
    }
}

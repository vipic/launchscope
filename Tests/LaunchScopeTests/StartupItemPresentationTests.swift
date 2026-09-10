import XCTest
@testable import LaunchScope

final class StartupItemPresentationTests: XCTestCase {
    func testUnattributedItemsAreNotGroupedTogether() {
        let first = StartupItem(
            id: "launchd:/one.plist",
            label: "com.example.one",
            displayName: "One",
            source: .userLaunchAgent
        )
        let second = StartupItem(
            id: "launchd:/two.plist",
            label: "com.example.two",
            displayName: "Two",
            source: .userLaunchAgent
        )

        XCTAssertEqual(StartupItemListData.groups(for: [first, second]).count, 2)
    }

    func testHomebrewAndLaunchdRecordsShareOneGroup() {
        let service = StartupItem(
            id: "homebrew:ollama",
            label: "homebrew.mxcl.ollama",
            displayName: "ollama",
            source: .homebrewService
        )
        let plist = StartupItem(
            id: "launchd:/ollama.plist",
            label: "homebrew.mxcl.ollama",
            source: .userLaunchAgent
        )

        let group = StartupItemListData.groups(for: [plist, service])
        XCTAssertEqual(group.count, 1)
        XCTAssertEqual(group[0].name, "ollama")
        XCTAssertEqual(group[0].items.first?.source, .homebrewService)
    }

    func testHomebrewExplanationDoesNotClaimExactCreator() {
        let item = StartupItem(
            id: "homebrew:ollama",
            label: "homebrew.mxcl.ollama",
            displayName: "ollama",
            source: .homebrewService,
            keepAliveDescription: "始终"
        )

        XCTAssertEqual(item.explanation.origin, "Homebrew 服务")
        XCTAssertTrue(item.explanation.reason.contains("通常"))
        XCTAssertTrue(item.explanation.trigger.contains("KeepAlive"))
    }

    func testGroupedStatusDescribesComponentsWithoutClaimingOwnerAppIsNotRunning() throws {
        let owner = AppAttribution(displayName: "1Password", bundleIdentifier: "com.1password.1password")
        let disabledBackgroundTask = StartupItem(
            id: "background:1password",
            label: "2.com.1password.1password",
            displayName: "1Password",
            source: .backgroundTask,
            attribution: owner,
            runtime: RuntimeInfo(state: .unknown),
            isEnabled: false
        )
        let enabledLoginItem = StartupItem(
            id: "login:1password-launcher",
            label: "4.com.1password.1password-launcher",
            displayName: "1Password Launcher",
            source: .loginItem,
            attribution: owner,
            runtime: RuntimeInfo(state: .unknown),
            isEnabled: true
        )

        let group = try XCTUnwrap(StartupItemListData.groups(for: [disabledBackgroundTask, enabledLoginItem]).first)

        XCTAssertEqual(group.statusSummary, "1 条组件已启用 · 1 条已停用")
        XCTAssertFalse(group.statusSummary.contains("未运行"))
    }

    func testEnabledOnDemandComponentIsNotReportedAsNotRunning() throws {
        let item = StartupItem(
            id: "login:on-demand",
            label: "com.example.on-demand",
            source: .loginItem,
            runtime: RuntimeInfo(state: .unknown),
            isEnabled: true
        )

        let group = try XCTUnwrap(StartupItemListData.groups(for: [item]).first)

        XCTAssertEqual(group.statusSummary, "组件已启用，按需运行")
    }

    func testRunningAndDisabledFiltersAreMutuallyExclusiveAtOwnerLevel() {
        let owner = AppAttribution(displayName: "Example", bundleIdentifier: "com.example.app")
        let running = StartupItem(
            id: "launchd:running",
            label: "com.example.running",
            source: .userLaunchAgent,
            attribution: owner,
            runtime: RuntimeInfo(state: .running),
            isEnabled: true
        )
        let disabled = StartupItem(
            id: "background:disabled",
            label: "com.example.disabled",
            source: .backgroundTask,
            attribution: owner,
            runtime: RuntimeInfo(state: .unknown),
            isEnabled: false
        )

        let runningGroups = StartupItemListData.statusGroups(for: [running, disabled], filter: .running)
        let disabledGroups = StartupItemListData.statusGroups(for: [running, disabled], filter: .disabled)

        XCTAssertEqual(runningGroups.count, 1)
        XCTAssertTrue(disabledGroups.isEmpty)
        XCTAssertEqual(runningGroups[0].statusSummary, "1 条组件正在运行 · 1 条已停用")
    }

    func testPartiallyDisabledOwnerIsNotClassifiedAsFullyDisabled() throws {
        let owner = AppAttribution(displayName: "1Password", bundleIdentifier: "com.1password.1password")
        let disabled = StartupItem(
            id: "background:disabled",
            label: "com.1password.background",
            source: .backgroundTask,
            attribution: owner,
            runtime: RuntimeInfo(state: .unknown),
            isEnabled: false
        )
        let enabled = StartupItem(
            id: "login:enabled",
            label: "com.1password.launcher",
            displayName: "1Password Launcher",
            source: .loginItem,
            attribution: owner,
            runtime: RuntimeInfo(state: .unknown),
            isEnabled: true
        )

        let group = try XCTUnwrap(StartupItemListData.groups(for: [disabled, enabled]).first)

        XCTAssertFalse(group.isFullyDisabled)
        XCTAssertEqual(group.statusSummary, "1 条组件已启用 · 1 条已停用")
    }
}

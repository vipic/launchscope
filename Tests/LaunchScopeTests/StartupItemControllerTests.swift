import XCTest
@testable import LaunchScope

final class StartupItemControllerTests: XCTestCase {
    func testOnlyCurrentUserLaunchAgentIsControllable() {
        let controller = StartupItemController(
            runner: RecordingCommandRunner(results: []),
            homeDirectory: "/Users/tester",
            userIdentifier: 501
        )

        XCTAssertEqual(controller.availableAction(for: makeItem()), .disable)
        XCTAssertNil(controller.availableAction(for: makeItem(path: "/Library/LaunchAgents/example.plist")))
        XCTAssertNil(controller.availableAction(for: makeItem(isAppleItem: true)))
        XCTAssertNil(controller.availableAction(for: makeItem(domain: "gui/502")))
    }

    func testDisabledItemOffersEnable() {
        let controller = makeController(results: [])
        XCTAssertEqual(controller.availableAction(for: makeItem(isEnabled: false)), .enable)
    }

    func testDisableUpdatesOverrideThenBootsOut() {
        let runner = RecordingCommandRunner(results: [.success(), .success()])
        let controller = makeController(runner: runner)

        let result = controller.perform(.disable, on: makeItem())

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["disable", "gui/501/com.example.agent"],
            ["bootout", "gui/501", "/Users/tester/Library/LaunchAgents/example.plist"],
        ])
    }

    func testEnableUpdatesOverrideThenBootstraps() {
        let runner = RecordingCommandRunner(results: [.success(), .success()])
        let controller = makeController(runner: runner)

        let result = controller.perform(.enable, on: makeItem(isEnabled: false))

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["enable", "gui/501/com.example.agent"],
            ["bootstrap", "gui/501", "/Users/tester/Library/LaunchAgents/example.plist"],
        ])
    }

    func testOverrideFailureStopsOperation() {
        let runner = RecordingCommandRunner(results: [.failure("不允许操作")])
        let controller = makeController(runner: runner)

        let result = controller.perform(.disable, on: makeItem())

        XCTAssertEqual(result.outcome, .failure)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(result.message.contains("不允许操作"))
    }

    func testRuntimeFailureReturnsPartialResult() {
        let runner = RecordingCommandRunner(results: [.success(), .failure("未找到服务")])
        let controller = makeController(runner: runner)

        let result = controller.perform(.disable, on: makeItem())

        XCTAssertEqual(result.outcome, .partial)
        XCTAssertTrue(result.message.contains("未找到服务"))
    }

    func testHomebrewServiceOffersStateSpecificAction() {
        let controller = makeController(results: [], homebrewExecutable: "/opt/homebrew/bin/brew")

        XCTAssertEqual(controller.availableAction(for: makeHomebrewItem(state: .running)), .stopHomebrew)
        XCTAssertEqual(controller.availableAction(for: makeHomebrewItem(state: .notLoaded)), .startHomebrew)
    }

    func testHomebrewRejectsUnsafeServiceNameOrMissingExecutable() {
        let controller = makeController(results: [], homebrewExecutable: "/opt/homebrew/bin/brew")
        let missingBrew = makeController(results: [], homebrewExecutable: nil)

        XCTAssertNil(controller.availableAction(for: makeHomebrewItem(name: "--all")))
        XCTAssertNil(controller.availableAction(for: makeHomebrewItem(name: "redis;open /Applications")))
        XCTAssertNil(missingBrew.availableAction(for: makeHomebrewItem()))
    }

    func testStopsHomebrewServiceWithoutShellOrSudo() {
        let runner = RecordingCommandRunner(results: [.success()])
        let controller = makeController(
            runner: runner,
            homebrewExecutable: "/opt/homebrew/bin/brew"
        )

        let result = controller.perform(.stopHomebrew, on: makeHomebrewItem(state: .running))

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(runner.calls.first?.executable, "/opt/homebrew/bin/brew")
        XCTAssertEqual(runner.calls.first?.arguments, ["services", "stop", "ollama"])
        XCTAssertEqual(runner.calls.first?.timeout, 15)
    }

    func testStartsHomebrewServiceAndReportsFailure() {
        let runner = RecordingCommandRunner(results: [.failure("formula not installed")])
        let controller = makeController(
            runner: runner,
            homebrewExecutable: "/opt/homebrew/bin/brew"
        )

        let result = controller.perform(.startHomebrew, on: makeHomebrewItem(state: .notLoaded))

        XCTAssertEqual(result.outcome, .failure)
        XCTAssertTrue(result.message.contains("formula not installed"))
    }

    private func makeController(
        results: [CommandResult],
        homebrewExecutable: String? = nil
    ) -> StartupItemController {
        makeController(
            runner: RecordingCommandRunner(results: results),
            homebrewExecutable: homebrewExecutable
        )
    }

    private func makeController(
        runner: RecordingCommandRunner,
        homebrewExecutable: String? = nil
    ) -> StartupItemController {
        StartupItemController(
            runner: runner,
            homeDirectory: "/Users/tester",
            userIdentifier: 501,
            homebrewExecutable: homebrewExecutable
        )
    }

    private func makeItem(
        path: String = "/Users/tester/Library/LaunchAgents/example.plist",
        domain: String = "gui/501",
        isEnabled: Bool? = true,
        isAppleItem: Bool = false
    ) -> StartupItem {
        StartupItem(
            id: "agent",
            label: "com.example.agent",
            source: .userLaunchAgent,
            sourcePath: path,
            runtime: RuntimeInfo(domain: domain),
            isEnabled: isEnabled,
            isAppleItem: isAppleItem
        )
    }

    private func makeHomebrewItem(
        name: String = "ollama",
        state: RuntimeState = .running
    ) -> StartupItem {
        StartupItem(
            id: "homebrew:\(name)",
            label: "homebrew.mxcl.\(name)",
            displayName: name,
            source: .homebrewService,
            configuration: ["服务名": name],
            runtime: RuntimeInfo(state: state),
            isEnabled: state == .running,
            isAppleItem: false
        )
    }
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call {
        var executable: String
        var arguments: [String]
        var timeout: TimeInterval
    }

    private(set) var calls: [Call] = []
    private var results: [CommandResult]

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments, timeout: timeout))
        guard !results.isEmpty else { return .failure("缺少测试结果") }
        return results.removeFirst()
    }
}

private extension CommandResult {
    static func success() -> CommandResult {
        CommandResult(standardOutput: "", standardError: "", exitCode: 0, timedOut: false)
    }

    static func failure(_ message: String) -> CommandResult {
        CommandResult(standardOutput: "", standardError: message, exitCode: 1, timedOut: false)
    }
}

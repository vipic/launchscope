import XCTest
@testable import LaunchScope

final class MetadataTests: XCTestCase {
    func testConfigurationFormatterHandlesStructuredKeepAlive() {
        let description = ConfigurationFormatter.keepAliveDescription([
            "NetworkState": true,
            "SuccessfulExit": false,
        ])
        XCTAssertTrue(description?.contains("NetworkState: true") == true)
        XCTAssertTrue(description?.contains("SuccessfulExit: false") == true)
    }

    func testRuntimeCapture() {
        let text = """
        state = running
        pid = 420
        last exit code = 0
        """
        XCTAssertEqual(RuntimeInspector.capture(pattern: #"state = ([^\n]+)"#, in: text), "running")
        XCTAssertEqual(RuntimeInspector.capture(pattern: #"pid = ([0-9]+)"#, in: text), "420")
    }

    func testParsesLaunchctlServiceSnapshot() throws {
        let services = RuntimeInspector.parseServices("""
        gui/501 = {
          services = {
              420      -  com.example.running
                0      7  com.example.loaded
          }
        }
        """, domain: "gui/501")

        XCTAssertEqual(services["com.example.running"]?.state, .running)
        XCTAssertEqual(services["com.example.running"]?.processIdentifier, 420)
        XCTAssertEqual(services["com.example.loaded"]?.state, .loaded)
        XCTAssertEqual(services["com.example.loaded"]?.lastExitCode, 7)
    }

    func testFindsEnclosingApplicationBundle() {
        let url = AttributionResolver.enclosingAppURL(
            path: "/Applications/Example.app/Contents/Library/LoginItems/Helper.app/Contents/MacOS/Helper"
        )
        XCTAssertEqual(url?.path, "/Applications/Example.app")
    }

    func testSearchTextContainsMetadata() {
        var item = StartupItem(
            id: "test",
            label: "com.example.helper",
            displayName: "Example Helper",
            source: .userLaunchAgent,
            executablePath: "/Applications/Example.app/Contents/MacOS/Example"
        )
        item.attribution = AppAttribution(displayName: "Example", bundleIdentifier: "com.example.app")
        item.signature.teamIdentifier = "TEAM123"
        XCTAssertTrue(item.searchableText.contains("com.example.app"))
        XCTAssertTrue(item.searchableText.contains("team123"))
    }

    func testStatusTitleUsesSourceSpecificMeaning() {
        let enabledItem = StartupItem(
            id: "background",
            label: "com.example.background",
            source: .backgroundTask,
            isEnabled: true
        )
        let cronItem = StartupItem(
            id: "cron",
            label: "cron.1",
            source: .cron,
            isEnabled: true
        )
        let runningItem = StartupItem(
            id: "launchd",
            label: "com.example.agent",
            source: .userLaunchAgent,
            runtime: RuntimeInfo(state: .running)
        )

        XCTAssertEqual(enabledItem.statusLabel, "启用状态")
        XCTAssertEqual(enabledItem.statusTitle, "已启用")
        XCTAssertEqual(cronItem.statusLabel, "配置状态")
        XCTAssertEqual(cronItem.statusTitle, "已配置")
        XCTAssertEqual(runningItem.statusLabel, "运行状态")
        XCTAssertEqual(runningItem.statusTitle, "正在运行")
    }
}

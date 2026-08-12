import XCTest
@testable import LaunchScope

final class TextScannerTests: XCTestCase {
    func testCronParserSkipsCommentsAndKeepsCommand() throws {
        let items = CronScanner.parse("""
        # sync every morning
        0 4 * * * /usr/bin/rsync -a /source /target
        """)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(item.scheduleDescription, "0 4 * * *")
        XCTAssertEqual(item.executablePath, "/usr/bin/rsync")
        XCTAssertTrue(item.arguments.first?.contains("rsync") == true)
    }

    func testShellParserIncludesLineNumberAndExplanation() throws {
        let items = ShellConfigScanner.parse("""
        # comment
        export PATH=/opt/example/bin:$PATH

        launch-my-agent --quiet
        """, path: "/Users/test/.zprofile")

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].configuration["第 2 行"], "export PATH=/opt/example/bin:$PATH")
        XCTAssertEqual(items[0].configuration["第 4 行"], "launch-my-agent --quiet")
        XCTAssertEqual(items[0].label, "shell.zprofile")
        XCTAssertEqual(items[0].arguments.count, 2)
        XCTAssertFalse(items[0].discoveryNotes.isEmpty)
    }

    func testBackgroundTaskParserIsTolerant() throws {
        let items = BackgroundTaskScanner.parse("""
        #1:
        UUID: 5EA4
        Name: Example Helper
        Developer Name: Example Inc.
        Type: legacy agent (0x10008)
        Disposition: [enabled, allowed, visible] (11)
        Identifier: com.example.helper
        URL: file:///Applications/Example.app
        Executable Path: /Applications/Example.app/Contents/MacOS/Example
        Parent Identifier: com.example.app

        """)

        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.label, "com.example.helper")
        XCTAssertEqual(item.displayName, "Example Helper")
        XCTAssertEqual(item.attribution?.displayName, "Example Helper")
        XCTAssertEqual(item.configuration["Developer Name"], "Example Inc.")
        XCTAssertEqual(item.isEnabled, true)
        XCTAssertEqual(item.source, .backgroundTask)
    }

    func testBackgroundTaskAllowedButDisabledIsNotEnabled() throws {
        let item = try XCTUnwrap(BackgroundTaskScanner.parse("""
        #1:
        UUID: DISABLED
        Name: Disabled Helper
        Type: app (0x2)
        Disposition: [disabled, allowed, not notified] (0x2)
        Identifier: com.example.disabled
        URL: file:///Applications/Disabled.app/

        """).first)
        XCTAssertEqual(item.isEnabled, false)
        XCTAssertEqual(item.statusTitle, "已停用")
    }

    func testBackgroundTaskWithoutDispositionKeepsEnabledStateUnknown() throws {
        let item = try XCTUnwrap(BackgroundTaskScanner.parse("""
        #1:
        UUID: UNKNOWN
        Name: Unknown Helper
        Type: app (0x2)
        Identifier: com.example.unknown

        """).first)

        XCTAssertNil(item.isEnabled)
        XCTAssertEqual(item.statusTitle, "启用状态未知")
    }

    func testBackgroundTaskGroupsEmbeddedItemUnderParent() throws {
        let items = BackgroundTaskScanner.parse("""
        #1:
        UUID: PARENT
        Name: Example App
        Type: app (0x2)
        Disposition: [enabled, allowed] (0x3)
        Identifier: 2.com.example.app
        Bundle Identifier: com.example.app
        URL: file:///Applications/Example.app/

        #2:
        UUID: CHILD
        Name: (null)
        Type: agent (0x8)
        Disposition: [enabled, allowed] (0x3)
        Identifier: 16.com.example.helper
        Parent Identifier: 2.com.example.app
        URL: file:///Applications/Example.app/Contents/Library/LoginItems/Helper.app/

        """)

        let child = try XCTUnwrap(items.first { $0.label == "16.com.example.helper" })
        XCTAssertEqual(child.displayName, "Example App")
        XCTAssertEqual(child.attribution?.displayName, "Example App")
    }
}

import XCTest
@testable import LaunchScope

final class LaunchdScannerTests: XCTestCase {
    func testParsesLaunchdConfiguration() throws {
        let fixtureDirectory = try XCTUnwrap(Bundle.module.resourceURL?.appendingPathComponent("Fixtures"))
        let location = LaunchdLocation(
            path: fixtureDirectory.path,
            source: .userLaunchAgent,
            domain: "gui/501"
        )

        let result = LaunchdScanner(locations: [location]).scan()
        let item = try XCTUnwrap(result.items.first)

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(item.label, "com.example.backup")
        XCTAssertEqual(item.executablePath, "/bin/sh")
        XCTAssertEqual(item.arguments, ["/bin/sh", "-c", "echo backup"])
        XCTAssertEqual(item.runAtLoad, true)
        XCTAssertEqual(item.scheduleDescription, "每 3600 秒")
        XCTAssertEqual(item.environment["BACKUP_TOKEN"], "secret-value")
        XCTAssertEqual(item.runtime.domain, "gui/501")
    }

    func testMissingDirectoryIsNotAnError() {
        let result = LaunchdScanner(locations: [
            LaunchdLocation(path: "/path/that/does/not/exist", source: .userLaunchAgent, domain: "gui/501")
        ]).scan()
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
    }
}

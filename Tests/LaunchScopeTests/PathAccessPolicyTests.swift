import XCTest
@testable import LaunchScope

final class PathAccessPolicyTests: XCTestCase {
    func testProtectedUserDirectoriesAreNeverProbed() {
        let home = "/Users/test"
        let protectedPaths = [
            "/Users/test/Documents/project/tool",
            "/Users/test/Desktop/script.sh",
            "/Users/test/Downloads/helper",
            "/Users/test/Library/CloudStorage/Drive/file",
            "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/tool",
        ]

        for path in protectedPaths {
            XCTAssertFalse(PathAccessPolicy.canProbeMetadata(at: path, homeDirectory: home), path)
        }
    }

    func testApplicationAndSystemPathsCanBeProbed() {
        XCTAssertTrue(PathAccessPolicy.canProbeMetadata(at: "/Applications/Example.app", homeDirectory: "/Users/test"))
        XCTAssertTrue(PathAccessPolicy.canProbeMetadata(at: "/Library/PrivilegedHelperTools/example", homeDirectory: "/Users/test"))
        XCTAssertTrue(PathAccessPolicy.canProbeMetadata(at: "/Users/test/Applications/Example.app", homeDirectory: "/Users/test"))
    }

    func testLaunchdItemInDocumentsKeepsPathWithoutReadingTarget() {
        let location = LaunchdLocation(
            path: "/Users/test/Library/LaunchAgents",
            source: .userLaunchAgent,
            domain: "gui/501"
        )
        let item = LaunchdScanner.makeItem(
            plist: [
                "Label": "com.example.documents-tool",
                "Program": "/Users/mason/Documents/project/tool",
            ],
            file: URL(fileURLWithPath: "/Users/test/Library/LaunchAgents/com.example.plist"),
            location: location
        )

        XCTAssertEqual(item.executablePath, "/Users/mason/Documents/project/tool")
        XCTAssertNil(item.targetExists)
        XCTAssertTrue(item.discoveryNotes.contains { $0.contains("受保护目录") })
    }
}

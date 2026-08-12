import Foundation
import XCTest

final class ReleaseWorkflowContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(of relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testReleaseRequiresUnifiedValidationAndSafePublishing() throws {
        let release = try contents(of: "release.sh")
        XCTAssertTrue(release.contains("command_log_run check mise run check"))
        XCTAssertTrue(release.contains("git push --atomic"))
        XCTAssertTrue(release.contains("gh release create"))
        XCTAssertFalse(release.contains("--clobber"))
    }

    func testCIOnlyRunsSourceValidation() throws {
        let workflow = try contents(of: ".github/workflows/tests.yml")
        XCTAssertTrue(workflow.contains("mise run check"))
        XCTAssertFalse(workflow.contains("release.sh"))
        XCTAssertFalse(workflow.contains("upload-artifact"))
    }

    func testScriptsKeepStableSigningIdentity() throws {
        let deploy = try contents(of: "deploy.sh")
        let release = try contents(of: "release.sh")
        for script in [deploy, release] {
            XCTAssertTrue(script.contains(#"${CODESIGN_IDENTITY:-Nekutai}"#))
            XCTAssertFalse(script.contains("codesign --force --sign -"))
            XCTAssertFalse(script.contains("codesign --force --deep --sign -"))
        }
    }
}

import XCTest
@testable import LaunchScope

final class HomebrewScannerTests: XCTestCase {
    func testParsesHomebrewServices() throws {
        let data = Data("""
        [
          {"name":"ollama","status":"started","user":"mason","file":"/tmp/ollama.plist","exit_code":null},
          {"name":"redis","status":"none","user":null,"file":"/tmp/redis.plist","exit_code":1}
        ]
        """.utf8)

        let items = try HomebrewScanner.parse(data)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].runtime.state, .running)
        XCTAssertEqual(items[1].runtime.state, .notLoaded)
        XCTAssertEqual(items[1].runtime.lastExitCode, 1)
    }
}

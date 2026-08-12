import XCTest
@testable import LaunchScope

final class ResourceObservationTests: XCTestCase {
    func testParsesPSOutputWithDaysAndHours() throws {
        let values = ResourceObservationParser.parse("""
          123  12.5  4096  01:02:03
          456   0.0  1024  2-03:04:05
        """)
        XCTAssertEqual(values[123]?.cpuPercent, 12.5)
        XCTAssertEqual(values[123]?.residentMemoryBytes, 4_194_304)
        XCTAssertEqual(values[123]?.elapsedSeconds, 3_723)
        XCTAssertEqual(values[456]?.elapsedSeconds, 183_845)
    }

    func testParserSkipsMalformedRowsAndClampsNegativeCPU() {
        let values = ResourceObservationParser.parse("bad row\n42 -1.0 20 02:30\n")
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[42]?.cpuPercent, 0)
        XCTAssertEqual(values[42]?.elapsedSeconds, 150)
    }
}

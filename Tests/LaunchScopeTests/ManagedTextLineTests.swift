import XCTest
@testable import LaunchScope

final class ManagedTextLineTests: XCTestCase {
    func testDisableAndEnableRoundTripPreservesEntireDocument() throws {
        let original = "# heading\n  agent --token='a b'\n\n"
        let disabled = try ManagedTextLine.replacingLine(
            in: original, lineNumber: 2, expectedOriginal: "  agent --token='a b'", enable: false
        )
        XCTAssertNotEqual(disabled, original)
        let restored = try ManagedTextLine.replacingLine(
            in: disabled, lineNumber: 2, expectedOriginal: "  agent --token='a b'", enable: true
        )
        XCTAssertEqual(restored, original)
    }

    func testRefusesWrongLineNumberOrChangedContent() {
        XCTAssertThrowsError(try ManagedTextLine.replacingLine(
            in: "one\ntwo\n", lineNumber: 2, expectedOriginal: "changed", enable: false
        ))
        XCTAssertThrowsError(try ManagedTextLine.replacingLine(
            in: "one\ntwo\n", lineNumber: 99, expectedOriginal: "two", enable: false
        ))
    }

    func testMarkerRejectsInvalidPayload() {
        XCTAssertNil(ManagedTextLine.originalLine(from: "# LaunchScope disabled:v1:not-base64"))
    }
}

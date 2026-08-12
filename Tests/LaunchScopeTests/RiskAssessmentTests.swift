import XCTest
@testable import LaunchScope

final class RiskAssessmentTests: XCTestCase {
    func testMissingTargetIsHighRiskWithResidualExplanation() {
        let item = StartupItem(
            id: "missing", label: "com.example.missing", source: .userLaunchAgent,
            signature: SignatureInfo(kind: .developerID), targetExists: false
        )
        let assessment = RiskAssessment.assess(item)
        XCTAssertEqual(assessment.level, .high)
        XCTAssertTrue(assessment.reasons.contains { $0.contains("残留") })
    }

    func testUnsignedDaemonIsHighRiskAndExplainsPrivilegeAndSignature() {
        let item = StartupItem(
            id: "daemon", label: "com.example.daemon", source: .launchDaemon,
            signature: SignatureInfo(kind: .unsigned), targetExists: true
        )
        let assessment = RiskAssessment.assess(item)
        XCTAssertEqual(assessment.level, .high)
        XCTAssertTrue(assessment.reasons.contains { $0.contains("高权限") })
        XCTAssertTrue(assessment.reasons.contains { $0.contains("所有用户") })
    }

    func testNewDeveloperIDAgentNeedsAttentionWithoutBeingHighRisk() {
        let item = StartupItem(
            id: "new", label: "com.example.new", source: .userLaunchAgent,
            signature: SignatureInfo(kind: .developerID), targetExists: true
        )
        let assessment = RiskAssessment.assess(item, isNew: true)
        XCTAssertEqual(assessment.level, .medium)
        XCTAssertTrue(assessment.reasons.contains { $0.contains("新增") })
    }

    func testVerifiedAppleItemStaysLowRisk() {
        let item = StartupItem(
            id: "apple", label: "com.apple.example", source: .systemLaunchDaemon,
            signature: SignatureInfo(kind: .apple), targetExists: true, isAppleItem: true
        )
        let assessment = RiskAssessment.assess(item)
        XCTAssertEqual(assessment.level, .low)
        XCTAssertTrue(assessment.reasons.contains { $0.contains("Apple") })
    }
}

import XCTest
@testable import LaunchScope

final class StartupDataPerformanceTests: XCTestCase {
    func testFiveThousandItemAnalysisCompletesWithinBudget() {
        let items = (0..<5_000).map { index in
            StartupItem(
                id: "item-\(index)", label: "com.example.item-\(index)",
                displayName: "示例项目 \(index)",
                source: index.isMultiple(of: 5) ? .launchDaemon : .userLaunchAgent,
                executablePath: "/opt/example/bin/worker-\(index % 1_000)",
                signature: SignatureInfo(kind: index.isMultiple(of: 11) ? .unsigned : .developerID),
                runtime: RuntimeInfo(state: index.isMultiple(of: 3) ? .running : .notLoaded),
                targetExists: true,
                isEnabled: true
            )
        }

        let started = ContinuousClock.now
        let risks = items.map { RiskAssessment.assess($0, isNew: false) }
        let findings = StartupConflictDetector.detect(items)
        let searchable = items.filter { $0.searchableText.contains("item-4999") }
        let elapsed = started.duration(to: .now)

        XCTAssertEqual(risks.count, 5_000)
        XCTAssertFalse(findings.isEmpty)
        XCTAssertEqual(searchable.count, 1)
        XCTAssertLessThan(elapsed, .seconds(2))
    }
}

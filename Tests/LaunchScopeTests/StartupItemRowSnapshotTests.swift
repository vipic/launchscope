import SwiftUI
import XCTest
@testable import LaunchScope

@MainActor
final class StartupItemRowSnapshotTests: XCTestCase {
    func testRunningDeveloperAgentRow() throws {
        let item = StartupItem(
            id: "snapshot:running",
            label: "com.example.sync",
            displayName: "Example Sync",
            source: .userLaunchAgent,
            executablePath: "/Applications/Example.app/Contents/MacOS/Example",
            signature: SignatureInfo(kind: .developerID),
            runtime: RuntimeInfo(state: .running, processIdentifier: 4242, domain: "gui/501"),
            targetExists: true,
            isEnabled: true
        )
        try assertRow(item: item, selected: true, trusted: false, isNew: true)
    }

    func testMissingUnsignedDaemonRow() throws {
        let item = StartupItem(
            id: "snapshot:missing",
            label: "com.example.legacy-daemon",
            displayName: "Legacy Helper",
            source: .launchDaemon,
            executablePath: "/usr/local/libexec/legacy-helper",
            signature: SignatureInfo(kind: .unsigned),
            runtime: RuntimeInfo(state: .notLoaded, domain: "system"),
            targetExists: false,
            isEnabled: true
        )
        try assertRow(item: item, selected: false, trusted: false, isNew: false)
    }

    private func assertRow(item: StartupItem, selected: Bool, trusted: Bool, isNew: Bool) throws {
        try SnapshotTestSupport.assertSnapshot(
            named: item.id.replacingOccurrences(of: ":", with: "-"),
            size: CGSize(width: 620, height: 92),
            view: StartupItemRow(
                item: item,
                isSelected: selected,
                isTrusted: trusted,
                isNew: isNew,
                riskAssessment: RiskAssessment.assess(item, isNew: isNew)
            )
            .frame(width: 620, height: 92)
            .background(Color(nsColor: .controlBackgroundColor))
        )
    }
}

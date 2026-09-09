import XCTest
@testable import LaunchScope

final class StartupConflictDetectorTests: XCTestCase {
    func testDetectsMissingTargetAsResidual() {
        let item = StartupItem(
            id: "missing", label: "com.example.missing", source: .userLaunchAgent,
            executablePath: "/opt/example/missing", targetExists: false
        )
        let findings = StartupConflictDetector.detect([item])
        XCTAssertEqual(findings.map(\.kind), [.missingTarget])
        XCTAssertTrue(findings[0].explanation.contains("残留"))
    }

    func testDetectsHomebrewAndLaunchdOverlapByLabel() {
        let brew = StartupItem(id: "brew", label: "homebrew.mxcl.redis", source: .homebrewService)
        let agent = StartupItem(id: "agent", label: "homebrew.mxcl.redis", source: .userLaunchAgent)
        let findings = StartupConflictDetector.detect([brew, agent])
        XCTAssertEqual(findings.filter { $0.kind == .homebrewOverlap }.count, 1)
        XCTAssertEqual(Set(findings.first { $0.kind == .homebrewOverlap }?.itemIDs ?? []), ["brew", "agent"])
        XCTAssertEqual(findings.first?.category, .related)
    }

    func testDetectsDuplicateExecutableAcrossLaunchDomains() {
        let user = StartupItem(
            id: "user", label: "com.example.user", source: .userLaunchAgent,
            executablePath: "/opt/example/bin/worker"
        )
        let daemon = StartupItem(
            id: "daemon", label: "com.example.daemon", source: .launchDaemon,
            executablePath: "/opt/example/bin/worker"
        )
        XCTAssertTrue(StartupConflictDetector.detect([user, daemon]).contains { $0.kind == .duplicateExecutable })
    }

    func testDetectsExactDuplicateShellCommand() {
        let first = StartupItem(
            id: "zprofile", label: "shell.zprofile.1", source: .shellConfiguration,
            arguments: ["/opt/example/bin/start --quiet"]
        )
        let second = StartupItem(
            id: "zshrc", label: "shell.zshrc.2", source: .shellConfiguration,
            arguments: ["/opt/example/bin/start --quiet"]
        )
        XCTAssertTrue(StartupConflictDetector.detect([first, second]).contains { $0.kind == .duplicateShellCommand })
    }

    func testDoesNotConflateCaseOrQuotedWhitespace() {
        let commands = ["echo 'A  B'", "echo 'A B'", "echo 'a b'"]
        let items = commands.enumerated().map { index, command in
            StartupItem(id: "\(index)", label: "shell.\(index)", source: .shellConfiguration, arguments: [command])
        }
        XCTAssertFalse(StartupConflictDetector.detect(items).contains { $0.kind == .duplicateShellCommand })
    }

    func testAppleSharedExecutableIsReferenceNotConflict() {
        let items = [StartupSource.systemLaunchAgent, .systemLaunchDaemon].enumerated().map { index, source in
            StartupItem(id: "\(index)", label: "com.apple.example", source: source,
                        executablePath: "/System/Library/example", isAppleItem: true)
        }
        let findings = StartupConflictDetector.detect(items)
        XCTAssertFalse(findings.isEmpty)
        XCTAssertTrue(findings.allSatisfy { $0.category == .system })
    }

    func testDifferentDomainsOrArgumentsAreRelatedNotConflicting() {
        let items = ["gui/501", "system"].enumerated().map { index, domain in
            StartupItem(id: "\(index)", label: "worker.\(index)", source: .userLaunchAgent,
                        executablePath: "/opt/example/worker", runtime: RuntimeInfo(domain: domain))
        }
        XCTAssertEqual(StartupConflictDetector.detect(items).first?.category, .related)
    }
}

import XCTest
import LaunchScopePrivilegedProtocol
@testable import LaunchScope

final class PrivilegedHelperSecurityTests: XCTestCase {
    func testIdentityRequirementsPinIdentifiersAndCertificate() {
        XCTAssertTrue(PrivilegedServiceIdentity.appRequirement.contains("com.nekutai.launchscope"))
        XCTAssertTrue(PrivilegedServiceIdentity.appRequirement.contains("com.nekutai.launchscope.dev"))
        XCTAssertTrue(PrivilegedServiceIdentity.appRequirement.contains("certificate leaf[subject.CN] = \"Nekutai\""))
        XCTAssertTrue(PrivilegedServiceIdentity.helperRequirement.contains(PrivilegedServiceIdentity.helperIdentifier))
        XCTAssertTrue(PrivilegedServiceIdentity.helperRequirement.contains("certificate leaf[subject.CN] = \"Nekutai\""))
    }

    func testMachServiceAndPlistUseSameIdentity() {
        XCTAssertEqual(PrivilegedServiceIdentity.machServiceName, PrivilegedServiceIdentity.helperIdentifier)
        XCTAssertEqual(PrivilegedServiceIdentity.plistName, PrivilegedServiceIdentity.helperIdentifier + ".plist")
    }
}

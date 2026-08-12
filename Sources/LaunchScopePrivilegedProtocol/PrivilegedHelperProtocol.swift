import Foundation

public enum PrivilegedServiceIdentity {
    public static let machServiceName = "com.nekutai.launchscope.helper"
    public static let plistName = "com.nekutai.launchscope.helper.plist"
    public static let helperIdentifier = "com.nekutai.launchscope.helper"
    public static let helperVersion = 1

    public static let appRequirement = """
    (identifier "com.nekutai.launchscope" or identifier "com.nekutai.launchscope.dev") and certificate leaf[subject.CN] = "Nekutai"
    """
    public static let helperRequirement = """
    identifier "com.nekutai.launchscope.helper" and certificate leaf[subject.CN] = "Nekutai"
    """
}

@objc public protocol LaunchScopePrivilegedHelperProtocol {
    func ping(reply: @escaping (Int, String) -> Void)
    func setGlobalLaunchAgentEnabled(
        path: String,
        label: String,
        expectedSHA256: String,
        enabled: Bool,
        reply: @escaping (String, String, String) -> Void
    )
}

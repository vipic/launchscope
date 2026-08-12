import CryptoKit
import Foundation
import Security

public struct PrivilegedOperationResult: Equatable, Sendable {
    public var outcome: String
    public var title: String
    public var message: String

    public init(outcome: String, title: String, message: String) {
        self.outcome = outcome
        self.title = title
        self.message = message
    }
}

public protocol PrivilegedCommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) -> PrivilegedCommandResult
}

public struct PrivilegedCommandResult: Sendable {
    public var output: String
    public var error: String
    public var exitCode: Int32
    public var timedOut: Bool

    public init(output: String, error: String, exitCode: Int32, timedOut: Bool = false) {
        self.output = output
        self.error = error
        self.exitCode = exitCode
        self.timedOut = timedOut
    }
}

public struct RootCommandRunner: PrivilegedCommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: TimeInterval) -> PrivilegedCommandResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch {
            return PrivilegedCommandResult(output: "", error: error.localizedDescription, exitCode: 126)
        }
        let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
        }
        return PrivilegedCommandResult(
            output: String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            error: String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            exitCode: timedOut ? 124 : process.terminationStatus,
            timedOut: timedOut
        )
    }
}

public struct PrivilegedLaunchItemPolicy: Sendable {
    public var allowedDirectory: String
    public var requiredOwner: uid_t
    public var appleSignatureChecker: @Sendable (String) -> Bool

    public init(
        allowedDirectory: String = "/Library/LaunchAgents",
        requiredOwner: uid_t = 0,
        appleSignatureChecker: @escaping @Sendable (String) -> Bool = { path in Self.hasAppleSignature(path) }
    ) {
        self.allowedDirectory = URL(fileURLWithPath: allowedDirectory).standardizedFileURL.path
        self.requiredOwner = requiredOwner
        self.appleSignatureChecker = appleSignatureChecker
    }

    public func validate(path: String, label: String, expectedSHA256: String) throws {
        guard label.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$"#, options: .regularExpression) != nil,
              expectedSHA256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw PrivilegedLaunchItemError.invalidRequest
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension.lowercased() == "plist",
              url.deletingLastPathComponent().path == allowedDirectory,
              url.resolvingSymlinksInPath().path == url.path else {
            throw PrivilegedLaunchItemError.unsafePath
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == requiredOwner else {
            throw PrivilegedLaunchItemError.unsafeOwnership
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedSHA256 else { throw PrivilegedLaunchItemError.fileChanged }
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == label else { throw PrivilegedLaunchItemError.labelMismatch }
        let arguments = plist["ProgramArguments"] as? [String]
        let executable = plist["Program"] as? String ?? arguments?.first
        guard let executable, executable.hasPrefix("/") else { throw PrivilegedLaunchItemError.missingExecutable }
        let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/"]
        guard !systemPrefixes.contains(where: executable.hasPrefix), !appleSignatureChecker(executable) else {
            throw PrivilegedLaunchItemError.appleItem
        }
    }

    public static func hasAppleSignature(_ path: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}

public struct PrivilegedLaunchItemController: Sendable {
    public var runner: any PrivilegedCommandRunning
    public var policy: PrivilegedLaunchItemPolicy

    public init(runner: any PrivilegedCommandRunning = RootCommandRunner(), policy: PrivilegedLaunchItemPolicy = .init()) {
        self.runner = runner
        self.policy = policy
    }

    public func setGlobalAgentEnabled(
        path: String, label: String, expectedSHA256: String, enabled: Bool, userIdentifier: uid_t
    ) -> PrivilegedOperationResult {
        guard userIdentifier > 0 else { return failure("请求用户无效") }
        do { try policy.validate(path: path, label: label, expectedSHA256: expectedSHA256) }
        catch { return failure(error.localizedDescription) }
        let domain = "gui/\(userIdentifier)"
        let override = runner.run(
            executable: "/bin/launchctl",
            arguments: [enabled ? "enable" : "disable", "\(domain)/\(label)"], timeout: 4
        )
        guard override.exitCode == 0 else { return failure("更新允许状态失败：\(commandMessage(override))") }
        let runtime = runner.run(
            executable: "/bin/launchctl",
            arguments: enabled ? ["bootstrap", domain, path] : ["bootout", domain, path], timeout: 4
        )
        if runtime.exitCode == 0 {
            return PrivilegedOperationResult(
                outcome: "success",
                title: enabled ? "已恢复全局 Agent" : "已停用全局 Agent",
                message: enabled ? "已恢复当前用户的允许状态并加载原配置。" : "已禁止当前用户后续加载并卸载当前任务；plist 保持不变。"
            )
        }
        return PrivilegedOperationResult(
            outcome: "partial", title: "允许状态已更新",
            message: "运行状态更新失败：\(commandMessage(runtime))"
        )
    }

    private func commandMessage(_ result: PrivilegedCommandResult) -> String {
        if result.timedOut { return "命令执行超时" }
        let error = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty { return error }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "退出码 \(result.exitCode)" : output
    }

    private func failure(_ message: String) -> PrivilegedOperationResult {
        PrivilegedOperationResult(outcome: "failure", title: "管理员操作失败", message: message)
    }
}

public enum PrivilegedLaunchItemError: LocalizedError {
    case invalidRequest, unsafePath, unsafeOwnership, fileChanged, labelMismatch, missingExecutable, appleItem

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: "请求参数不符合安全约束。"
        case .unsafePath: "配置路径不在允许目录，或路径包含符号链接。"
        case .unsafeOwnership: "配置不是 root 拥有的普通文件。"
        case .fileChanged: "配置在扫描后发生变化，请重新扫描。"
        case .labelMismatch: "配置标识与扫描结果不一致。"
        case .missingExecutable: "配置未声明绝对执行路径。"
        case .appleItem: "Apple 或系统执行目标不允许操作。"
        }
    }
}

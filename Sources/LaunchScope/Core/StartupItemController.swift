import Foundation

enum StartupItemControlAction: String, Equatable, Sendable {
    case disable
    case enable

    var title: String {
        switch self {
        case .disable: "停用"
        case .enable: "恢复启用"
        }
    }
}

enum StartupItemControlOutcome: Equatable, Sendable {
    case success
    case partial
    case failure
}

struct StartupItemControlResult: Identifiable, Sendable {
    var id = UUID()
    var outcome: StartupItemControlOutcome
    var title: String
    var message: String
}

struct StartupItemController: Sendable {
    var runner: any CommandRunning = CommandRunner()
    var homeDirectory = NSHomeDirectory()
    var userIdentifier = getuid()

    func availableAction(for item: StartupItem) -> StartupItemControlAction? {
        guard validatedTarget(for: item) != nil else { return nil }
        return item.isEnabled == false ? .enable : .disable
    }

    func perform(_ action: StartupItemControlAction, on item: StartupItem) -> StartupItemControlResult {
        guard let target = validatedTarget(for: item), let sourcePath = item.sourcePath else {
            return StartupItemControlResult(
                outcome: .failure,
                title: "无法执行操作",
                message: "该项目不满足用户 LaunchAgent 的安全操作条件。"
            )
        }

        let overrideVerb = action == .disable ? "disable" : "enable"
        let override = runner.run(
            executable: "/bin/launchctl",
            arguments: [overrideVerb, target.serviceTarget],
            timeout: 4
        )
        guard override.exitCode == 0 else {
            return failureResult(action: action, phase: "更新允许状态", command: override)
        }

        let runtime: CommandResult
        switch action {
        case .disable:
            runtime = runner.run(
                executable: "/bin/launchctl",
                arguments: ["bootout", target.domain, sourcePath],
                timeout: 4
            )
        case .enable:
            runtime = runner.run(
                executable: "/bin/launchctl",
                arguments: ["bootstrap", target.domain, sourcePath],
                timeout: 4
            )
        }

        if runtime.exitCode == 0 {
            return StartupItemControlResult(
                outcome: .success,
                title: action == .disable ? "已停用" : "已恢复启用",
                message: action == .disable
                    ? "launchd 已禁止后续自动加载，并已卸载当前任务。配置文件保持不变。"
                    : "launchd 已恢复允许状态，并已重新加载配置文件。"
            )
        }

        let detail = commandMessage(runtime)
        return StartupItemControlResult(
            outcome: .partial,
            title: "允许状态已更新",
            message: action == .disable
                ? "项目已标记为停用，但卸载当前任务失败：\(detail)"
                : "项目已恢复允许，但重新加载失败：\(detail)"
        )
    }

    private func validatedTarget(for item: StartupItem) -> (domain: String, serviceTarget: String)? {
        guard item.source == .userLaunchAgent,
              !item.isAppleItem,
              !item.label.isEmpty,
              !item.label.contains("/"),
              let sourcePath = item.sourcePath,
              let domain = item.runtime.domain,
              domain == "gui/\(userIdentifier)" else { return nil }

        let launchAgentsDirectory = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .standardizedFileURL.path
        let sourceURL = URL(fileURLWithPath: sourcePath).standardizedFileURL
        guard sourceURL.pathExtension.lowercased() == "plist",
              sourceURL.deletingLastPathComponent().path == launchAgentsDirectory else { return nil }

        return (domain, "\(domain)/\(item.label)")
    }

    private func failureResult(
        action: StartupItemControlAction,
        phase: String,
        command: CommandResult
    ) -> StartupItemControlResult {
        StartupItemControlResult(
            outcome: .failure,
            title: "\(action.title)失败",
            message: "\(phase)失败：\(commandMessage(command))"
        )
    }

    private func commandMessage(_ result: CommandResult) -> String {
        if result.timedOut { return "命令执行超时" }
        let error = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if !error.isEmpty { return error }
        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? "退出码 \(result.exitCode)" : output
    }
}

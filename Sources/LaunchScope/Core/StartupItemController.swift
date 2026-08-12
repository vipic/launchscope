import Foundation

enum StartupItemControlAction: String, Equatable, Sendable {
    case disable
    case enable
    case stopHomebrew
    case startHomebrew

    var title: String {
        switch self {
        case .disable: "停用"
        case .enable: "恢复启用"
        case .stopHomebrew: "停止服务"
        case .startHomebrew: "启动服务"
        }
    }

    var isDestructive: Bool {
        self == .disable || self == .stopHomebrew
    }

    var confirmationTitle: String {
        switch self {
        case .disable: "停用这个 LaunchAgent？"
        case .enable: "恢复启用这个 LaunchAgent？"
        case .stopHomebrew: "停止这个 Homebrew 服务？"
        case .startHomebrew: "启动这个 Homebrew 服务？"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .disable:
            "LaunchScope 会禁止该项目后续自动加载，并卸载当前任务；不会删除或改写 plist，可以随时恢复。"
        case .enable:
            "LaunchScope 会恢复 launchd 允许状态，并重新加载原有 plist。"
        case .stopHomebrew:
            "LaunchScope 会调用 brew services stop，立即停止服务并取消登录时自动启动；以后可以重新启动。"
        case .startHomebrew:
            "LaunchScope 会调用 brew services start，立即启动服务并注册为登录时自动启动。"
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
    var homebrewExecutable = HomebrewLocator.executablePath()

    func availableAction(for item: StartupItem) -> StartupItemControlAction? {
        if validatedLaunchAgentTarget(for: item) != nil {
            return item.isEnabled == false ? .enable : .disable
        }
        if validatedHomebrewService(for: item) != nil {
            return item.runtime.state == .running ? .stopHomebrew : .startHomebrew
        }
        return nil
    }

    func perform(_ action: StartupItemControlAction, on item: StartupItem) -> StartupItemControlResult {
        guard availableAction(for: item) == action else {
            return StartupItemControlResult(
                outcome: .failure,
                title: "无法执行操作",
                message: "项目状态已变化，或该项目不满足安全操作条件。请重新扫描后再试。"
            )
        }

        switch action {
        case .disable, .enable:
            return performLaunchAgent(action, on: item)
        case .stopHomebrew, .startHomebrew:
            return performHomebrew(action, on: item)
        }
    }

    private func performLaunchAgent(
        _ action: StartupItemControlAction,
        on item: StartupItem
    ) -> StartupItemControlResult {
        guard let target = validatedLaunchAgentTarget(for: item), let sourcePath = item.sourcePath else {
            return invalidTargetResult()
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
        case .stopHomebrew, .startHomebrew:
            return invalidTargetResult()
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

    private func performHomebrew(
        _ action: StartupItemControlAction,
        on item: StartupItem
    ) -> StartupItemControlResult {
        guard let service = validatedHomebrewService(for: item) else {
            return invalidTargetResult()
        }
        let verb = action == .stopHomebrew ? "stop" : "start"
        let command = runner.run(
            executable: service.executable,
            arguments: ["services", verb, service.name],
            timeout: 15
        )
        guard command.exitCode == 0 else {
            return failureResult(action: action, phase: "Homebrew 服务操作", command: command)
        }
        return StartupItemControlResult(
            outcome: .success,
            title: action == .stopHomebrew ? "服务已停止" : "服务已启动",
            message: action == .stopHomebrew
                ? "Homebrew 已停止该服务并取消登录时自动启动。"
                : "Homebrew 已启动该服务并注册为登录时自动启动。"
        )
    }

    private func validatedLaunchAgentTarget(for item: StartupItem) -> (domain: String, serviceTarget: String)? {
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

    private func validatedHomebrewService(for item: StartupItem) -> (executable: String, name: String)? {
        guard item.source == .homebrewService,
              !item.isAppleItem,
              let executable = homebrewExecutable else { return nil }
        let name = item.configuration["服务名"] ?? item.displayName
        guard name.count <= 200,
              name.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9@+._-]*(/[A-Za-z0-9][A-Za-z0-9@+._-]*){0,2}$"#,
                options: .regularExpression
              ) != nil else { return nil }
        return (executable, name)
    }

    private func invalidTargetResult() -> StartupItemControlResult {
        StartupItemControlResult(
            outcome: .failure,
            title: "无法执行操作",
            message: "该项目不满足安全操作条件。请重新扫描后再试。"
        )
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

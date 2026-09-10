import Foundation

struct StartupItemGuidance: Equatable, Sendable {
    var title: String
    var summary: String
    var diagnosticCommand: String?
    var opensLoginItemSettings: Bool
}

extension StartupItem {
    var guidance: StartupItemGuidance {
        if isAppleItem || source.isAppleSystemLocation {
            return StartupItemGuidance(
                title: "仅建议查看",
                summary: "这是 Apple 系统位置中的项目。LaunchScope 不提供停用或移除入口，以免影响系统功能。",
                diagnosticCommand: launchctlPrintCommand,
                opensLoginItemSettings: false
            )
        }

        switch source {
        case .userLaunchAgent:
            return StartupItemGuidance(
                title: isEnabled == false ? "可恢复启用" : "可安全停用",
                summary: "LaunchScope 只修改当前用户的 launchd 允许状态并加载或卸载任务，不删除或改写 plist；操作后会重新扫描验证。",
                diagnosticCommand: launchctlPrintCommand,
                opensLoginItemSettings: false
            )
        case .globalLaunchAgent:
            return StartupItemGuidance(
                title: "当前仅提供查看",
                summary: "这是系统范围的登录任务。当前精简版不直接修改它，可先定位配置并确认所属应用。",
                diagnosticCommand: launchctlPrintCommand,
                opensLoginItemSettings: false
            )
        case .launchDaemon:
            return StartupItemGuidance(
                title: "当前仅提供查看",
                summary: "这是影响整个系统的后台服务。当前精简版不直接修改它，可先定位配置并确认所属应用。",
                diagnosticCommand: launchctlPrintCommand,
                opensLoginItemSettings: false
            )
        case .backgroundTask, .loginItem:
            return StartupItemGuidance(
                title: "在系统设置中管理",
                summary: "macOS 负责该项目的允许状态。请在“登录项与扩展”中关闭后台活动或移除登录项。",
                diagnosticCommand: nil,
                opensLoginItemSettings: true
            )
        case .homebrewService:
            let serviceName = configuration["服务名"] ?? displayName
            return StartupItemGuidance(
                title: runtime.state == .running ? "可停止 Homebrew 服务" : "可启动 Homebrew 服务",
                summary: "LaunchScope 通过当前用户的 brew services 停止或启动，不使用 sudo，也不手工修改 Homebrew 生成的配置。",
                diagnosticCommand: "brew services info \(Self.shellQuote(serviceName))",
                opensLoginItemSettings: false
            )
        case .cron:
            return StartupItemGuidance(
                title: "作为相关自动任务查看",
                summary: "Cron 是定时任务，不一定在开机时运行。当前精简版不修改 crontab。",
                diagnosticCommand: "/usr/bin/crontab -l",
                opensLoginItemSettings: false
            )
        case .shellConfiguration:
            return StartupItemGuidance(
                title: "作为相关自动任务查看",
                summary: "Shell 初始化命令通常只在打开终端时运行。当前精简版不修改配置文件。",
                diagnosticCommand: sourcePath.map { "/usr/bin/sed -n '1,160p' \(Self.shellQuote($0))" },
                opensLoginItemSettings: false
            )
        case .systemLaunchAgent, .systemLaunchDaemon:
            // Apple 系统位置已在上方统一处理。
            return StartupItemGuidance(
                title: "仅建议查看",
                summary: "系统启动项目不应由 LaunchScope 修改。",
                diagnosticCommand: launchctlPrintCommand,
                opensLoginItemSettings: false
            )
        }
    }

    var revealableSourcePath: String? {
        guard let sourcePath, sourcePath.hasPrefix("/") else { return nil }
        return sourcePath
    }

    private var launchctlPrintCommand: String? {
        guard let domain = runtime.domain else { return nil }
        return "/bin/launchctl print \(Self.shellQuote("\(domain)/\(label)"))"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

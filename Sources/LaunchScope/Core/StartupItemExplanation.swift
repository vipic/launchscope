import Foundation

struct StartupItemExplanation: Equatable, Sendable {
    var origin: String
    var reason: String
    var trigger: String
    var confidence: String
}

extension StartupItem {
    var explanation: StartupItemExplanation {
        if label.hasPrefix("homebrew.mxcl.") || source == .homebrewService {
            return StartupItemExplanation(
                origin: "Homebrew 服务",
                reason: "这通常由“brew services start”注册，用来让服务在登录后自动运行。",
                trigger: keepAliveDescription != nil ? "登录后启动，并由 KeepAlive 保持运行" : "用户登录后启动",
                confidence: "根据服务标签和配置路径判断"
            )
        }

        switch source {
        case .homebrewService:
            return StartupItemExplanation(
                origin: "Homebrew 服务",
                reason: "这通常由“brew services start”注册，用来让服务在登录后自动运行。",
                trigger: keepAliveDescription != nil ? "登录后启动，并由 KeepAlive 保持运行" : "用户登录后启动",
                confidence: "根据服务标签和配置路径判断"
            )
        case .backgroundTask:
            return StartupItemExplanation(
                origin: "macOS 后台项目",
                reason: "所属应用向 macOS 注册了后台组件，用于通知、同步、更新或其他后台功能。",
                trigger: "由 macOS 在登录后或应用需要时启动",
                confidence: "根据 Background Task Management 记录判断"
            )
        case .loginItem:
            return StartupItemExplanation(
                origin: "macOS 登录项",
                reason: "所属应用将它注册为登录项。",
                trigger: "用户登录时启动",
                confidence: "根据系统登录项记录判断"
            )
        case .userLaunchAgent:
            return StartupItemExplanation(
                origin: "用户 LaunchAgent",
                reason: "当前用户目录中的 plist 注册了这个任务，通常由应用安装器、包管理器或用户命令创建。",
                trigger: launchTrigger,
                confidence: "根据 launchd 配置判断；无法仅凭现有文件确定具体创建者"
            )
        case .globalLaunchAgent:
            return StartupItemExplanation(
                origin: "全局 LaunchAgent",
                reason: "系统范围的 plist 为每个登录用户注册了这个任务，通常由应用安装器创建。",
                trigger: launchTrigger,
                confidence: "根据 launchd 配置判断；无法仅凭现有文件确定具体创建者"
            )
        case .launchDaemon:
            return StartupItemExplanation(
                origin: "LaunchDaemon",
                reason: "系统范围的 plist 注册了这个后台服务，通常由需要系统权限的应用或安装器创建。",
                trigger: launchTrigger,
                confidence: "根据 launchd 配置判断；无法仅凭现有文件确定具体创建者"
            )
        case .cron:
            return StartupItemExplanation(
                origin: "Cron 自动任务",
                reason: "这是一条用户定时规则，不一定属于开机启动。",
                trigger: scheduleDescription ?? "按 Cron 规则触发",
                confidence: "根据当前用户 crontab 判断"
            )
        case .shellConfiguration:
            return StartupItemExplanation(
                origin: "Shell 配置",
                reason: "命令写在 Shell 初始化文件中，不一定会随 macOS 登录启动。",
                trigger: scheduleDescription ?? "打开终端或登录 Shell 时执行",
                confidence: "根据 Shell 配置文件判断"
            )
        case .systemLaunchAgent, .systemLaunchDaemon:
            return StartupItemExplanation(
                origin: "Apple 系统服务",
                reason: "这是 macOS 自带的系统任务。",
                trigger: launchTrigger,
                confidence: "根据系统路径与代码签名判断"
            )
        }
    }

    private var launchTrigger: String {
        var triggers: [String] = []
        if runAtLoad == true { triggers.append("加载后立即运行") }
        if keepAliveDescription != nil { triggers.append("KeepAlive 保持运行") }
        if let scheduleDescription { triggers.append(scheduleDescription) }
        return triggers.isEmpty ? "由 launchd 按配置条件启动" : triggers.joined(separator: "；")
    }
}

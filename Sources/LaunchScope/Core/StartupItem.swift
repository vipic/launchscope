import Foundation

enum StartupSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case userLaunchAgent
    case globalLaunchAgent
    case launchDaemon
    case systemLaunchAgent
    case systemLaunchDaemon
    case backgroundTask
    case loginItem
    case homebrewService
    case cron
    case shellConfiguration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userLaunchAgent: "用户 LaunchAgent"
        case .globalLaunchAgent: "全局 LaunchAgent"
        case .launchDaemon: "LaunchDaemon"
        case .systemLaunchAgent: "系统 LaunchAgent"
        case .systemLaunchDaemon: "系统 LaunchDaemon"
        case .backgroundTask: "后台任务"
        case .loginItem: "登录项"
        case .homebrewService: "Homebrew 服务"
        case .cron: "Cron 任务"
        case .shellConfiguration: "Shell 配置"
        }
    }

    var systemImage: String {
        switch self {
        case .userLaunchAgent, .globalLaunchAgent, .systemLaunchAgent: "person.crop.circle.badge.clock"
        case .launchDaemon, .systemLaunchDaemon: "gearshape.2"
        case .backgroundTask: "rectangle.stack.badge.play"
        case .loginItem: "person.badge.clock"
        case .homebrewService: "mug"
        case .cron: "calendar.badge.clock"
        case .shellConfiguration: "terminal"
        }
    }

    var compactTitle: String {
        switch self {
        case .userLaunchAgent: "用户 Agent"
        case .globalLaunchAgent: "全局 Agent"
        case .launchDaemon: "Daemon"
        case .systemLaunchAgent: "系统 Agent"
        case .systemLaunchDaemon: "系统 Daemon"
        case .backgroundTask: "后台任务"
        case .loginItem: "登录项"
        case .homebrewService: "Homebrew"
        case .cron: "Cron"
        case .shellConfiguration: "Shell"
        }
    }

    var isAppleSystemLocation: Bool {
        self == .systemLaunchAgent || self == .systemLaunchDaemon
    }
}

enum SignatureKind: String, Codable, Sendable {
    case apple
    case developerID
    case appStore
    case adHoc
    case unsigned
    case invalid
    case unavailable

    var title: String {
        switch self {
        case .apple: "Apple"
        case .developerID: "Developer ID"
        case .appStore: "App Store"
        case .adHoc: "临时签名"
        case .unsigned: "未签名"
        case .invalid: "签名无效"
        case .unavailable: "无法判断"
        }
    }
}

struct SignatureInfo: Codable, Hashable, Sendable {
    var kind: SignatureKind = .unavailable
    var identifier: String?
    var teamIdentifier: String?
    var authorities: [String] = []
    var statusCode: Int32?
}

enum RuntimeState: String, Codable, Sendable {
    case running
    case loaded
    case notLoaded
    case disabled
    case unknown

    var title: String {
        switch self {
        case .running: "正在运行"
        case .loaded: "已加载"
        case .notLoaded: "未加载"
        case .disabled: "已停用"
        case .unknown: "状态未知"
        }
    }
}

struct RuntimeInfo: Codable, Hashable, Sendable {
    var state: RuntimeState = .unknown
    var processIdentifier: Int32?
    var lastExitCode: Int32?
    var domain: String?
}

struct AppAttribution: Codable, Hashable, Sendable {
    var displayName: String?
    var bundleIdentifier: String?
    var bundlePath: String?
    var iconPath: String?
    var source: String?
}

struct StartupItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var label: String
    var displayName: String
    var source: StartupSource
    var sourcePath: String?
    var executablePath: String?
    var arguments: [String]
    var workingDirectory: String?
    var runAtLoad: Bool?
    var keepAliveDescription: String?
    var scheduleDescription: String?
    var environment: [String: String]
    var configuration: [String: String]
    var attribution: AppAttribution?
    var signature: SignatureInfo
    var runtime: RuntimeInfo
    var targetExists: Bool?
    var isEnabled: Bool?
    var isAppleItem: Bool
    var discoveryNotes: [String]

    init(
        id: String,
        label: String,
        displayName: String? = nil,
        source: StartupSource,
        sourcePath: String? = nil,
        executablePath: String? = nil,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        runAtLoad: Bool? = nil,
        keepAliveDescription: String? = nil,
        scheduleDescription: String? = nil,
        environment: [String: String] = [:],
        configuration: [String: String] = [:],
        attribution: AppAttribution? = nil,
        signature: SignatureInfo = SignatureInfo(),
        runtime: RuntimeInfo = RuntimeInfo(),
        targetExists: Bool? = nil,
        isEnabled: Bool? = nil,
        isAppleItem: Bool = false,
        discoveryNotes: [String] = []
    ) {
        self.id = id
        self.label = label
        self.displayName = displayName ?? label
        self.source = source
        self.sourcePath = sourcePath
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.runAtLoad = runAtLoad
        self.keepAliveDescription = keepAliveDescription
        self.scheduleDescription = scheduleDescription
        self.environment = environment
        self.configuration = configuration
        self.attribution = attribution
        self.signature = signature
        self.runtime = runtime
        self.targetExists = targetExists
        self.isEnabled = isEnabled
        self.isAppleItem = isAppleItem
        self.discoveryNotes = discoveryNotes
    }

    var ownerName: String { attribution?.displayName ?? displayName }
    var statusLabel: String {
        switch source {
        case .backgroundTask, .loginItem: "启用状态"
        case .cron, .shellConfiguration: "配置状态"
        default: "运行状态"
        }
    }
    var statusTitle: String {
        switch source {
        case .backgroundTask, .loginItem:
            isEnabled.map { $0 ? "已启用" : "已停用" } ?? "启用状态未知"
        case .cron, .shellConfiguration:
            isEnabled == false ? "未启用" : "已配置"
        default:
            runtime.state.title
        }
    }
    var groupName: String {
        if let name = attribution?.displayName, !name.isEmpty { return name }
        switch source {
        case .shellConfiguration: return "Shell 配置"
        case .cron: return "Cron 任务"
        case .homebrewService: return "Homebrew 服务"
        default: return "未归因项目"
        }
    }
    var searchableText: String {
        [displayName, label, source.title, executablePath, sourcePath,
         attribution?.displayName, attribution?.bundleIdentifier,
         signature.teamIdentifier, arguments.joined(separator: " ")]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }
}

import Foundation

enum DashboardFilter: Hashable, Identifiable {
    case all
    case thirdParty
    case apple
    case running
    case missingTarget
    case disabled
    case untrusted
    case issues
    case source(StartupSource)

    var id: String {
        switch self {
        case .all: "all"
        case .thirdParty: "thirdParty"
        case .apple: "apple"
        case .running: "running"
        case .missingTarget: "missingTarget"
        case .disabled: "disabled"
        case .untrusted: "untrusted"
        case .issues: "issues"
        case .source(let source): "source.\(source.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .all: "全部项目"
        case .thirdParty: "第三方与自定义"
        case .apple: "Apple 系统项"
        case .running: "正在运行"
        case .missingTarget: "目标已缺失"
        case .disabled: "已停用"
        case .untrusted: "未信任项目"
        case .issues: "扫描提示"
        case .source(let source): source.title
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .thirdParty: "person.crop.square"
        case .apple: "apple.logo"
        case .running: "play.circle"
        case .missingTarget: "exclamationmark.triangle"
        case .disabled: "pause.circle"
        case .untrusted: "shield.lefthalf.filled"
        case .issues: "bell.badge"
        case .source(let source): source.systemImage
        }
    }
}

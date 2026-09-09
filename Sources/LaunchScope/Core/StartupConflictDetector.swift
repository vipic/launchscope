import Foundation

enum StartupFindingKind: String, Sendable {
    case missingTarget
    case duplicateLabel
    case duplicateExecutable
    case homebrewOverlap
    case duplicateShellCommand

    var title: String {
        switch self {
        case .missingTarget: "目标缺失 · 疑似残留"
        case .duplicateLabel: "相同标识"
        case .duplicateExecutable: "共用执行文件"
        case .homebrewOverlap: "Homebrew 与 launchd 关联"
        case .duplicateShellCommand: "相同 Shell 命令"
        }
    }

    var systemImage: String {
        switch self {
        case .missingTarget: "link.badge.plus"
        case .duplicateLabel: "tag.slash"
        case .duplicateExecutable: "arrow.triangle.branch"
        case .homebrewOverlap: "mug.fill"
        case .duplicateShellCommand: "terminal.fill"
        }
    }
}

struct StartupFinding: Identifiable, Equatable, Sendable {
    var kind: StartupFindingKind
    var title: String
    var explanation: String
    var itemIDs: [String]
    var category: FindingCategory = .review

    var id: String { "\(kind.rawValue):\(itemIDs.sorted().joined(separator: "|"))" }
}

enum FindingCategory: Int, CaseIterable, Identifiable, Sendable {
    case missing, review, related, system
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .missing: "目标缺失"
        case .review: "待核实线索"
        case .related: "多来源关联"
        case .system: "系统参考"
        }
    }
    var requiresReview: Bool { self == .missing || self == .review }
}

enum StartupConflictDetector {
    static func detect(_ items: [StartupItem]) -> [StartupFinding] {
        var findings = residualFindings(items)
        findings += groupedFindings(items, key: { $0.label }) { key, group in
            let sources = Set(group.map(\.source))
            if sources.contains(.homebrewService), !sources.isDisjoint(with: launchdSources) {
                return StartupFinding(
                    kind: .homebrewOverlap,
                    title: key,
                    explanation: "同一服务同时出现在 Homebrew 与 launchd 中，通常是同一注册的两种视图，不代表重复运行。建议从 Homebrew 入口管理。",
                    itemIDs: group.map(\.id), category: .related
                )
            }
            return StartupFinding(
                kind: .duplicateLabel,
                title: key,
                explanation: "多个记录使用相同标识。请核对加载域与来源；不同用户或系统域可以合法共存，仅凭标识不能确认冲突。",
                itemIDs: group.map(\.id), category: category(for: group)
            )
        }

        findings += groupedFindings(items, key: normalizedExecutable) { path, group in
            StartupFinding(
                kind: .duplicateExecutable,
                title: URL(fileURLWithPath: path).lastPathComponent,
                explanation: "多个记录指向同一执行文件。不同参数、加载域或触发条件可能对应不同职责；尚未证明重复执行。",
                itemIDs: group.map(\.id), category: category(for: group)
            )
        }

        let shellItems = items.filter { $0.source == .shellConfiguration }
        findings += groupedFindings(shellItems, key: normalizedCommand) { command, group in
            StartupFinding(
                kind: .duplicateShellCommand,
                title: String(command.prefix(80)),
                explanation: "相同原文出现在多个 Shell 配置位置。需要确认这些文件是否会在同一会话加载，以及命令是否可重复执行。",
                itemIDs: group.map(\.id)
            )
        }

        return findings.sorted {
            if $0.category != $1.category { return $0.category.rawValue < $1.category.rawValue }
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private static let launchdSources: Set<StartupSource> = [
        .userLaunchAgent, .globalLaunchAgent, .launchDaemon, .systemLaunchAgent, .systemLaunchDaemon,
    ]

    private static func residualFindings(_ items: [StartupItem]) -> [StartupFinding] {
        items.filter { $0.targetExists == false }.map { item in
            StartupFinding(
                kind: .missingTarget,
                title: item.displayName,
                explanation: "已解析的执行路径当前不存在，可能是卸载残留或应用迁移。请核实来源时间与应用位置，再决定是否停用。",
                itemIDs: [item.id], category: item.isAppleItem ? .system : .missing
            )
        }
    }

    private static func groupedFindings(
        _ items: [StartupItem],
        key: (StartupItem) -> String?,
        make: (String, [StartupItem]) -> StartupFinding
    ) -> [StartupFinding] {
        Dictionary(grouping: items.compactMap { item in key(item).map { ($0, item) } }, by: \.0)
            .compactMap { key, pairs in
                let group = pairs.map(\.1)
                guard group.count > 1 else { return nil }
                return make(key, group)
            }
    }

    private static func normalizedExecutable(_ item: StartupItem) -> String? {
        guard let path = item.executablePath, path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func normalizedCommand(_ item: StartupItem) -> String? {
        guard let command = item.arguments.first else { return nil }
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func category(for items: [StartupItem]) -> FindingCategory {
        if items.allSatisfy(\.isAppleItem) { return .system }
        // BTM 与 Homebrew 均可能是 launchd 注册的另一份视图。
        if items.contains(where: { [.backgroundTask, .loginItem, .homebrewService].contains($0.source) }) {
            return .related
        }
        let domains = Set(items.compactMap { $0.runtime.domain })
        let arguments = Set(items.map(\.arguments))
        return domains.count > 1 || arguments.count > 1 ? .related : .review
    }
}

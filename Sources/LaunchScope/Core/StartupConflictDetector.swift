import Foundation

enum StartupFindingKind: String, Sendable {
    case missingTarget
    case duplicateLabel
    case duplicateExecutable
    case homebrewOverlap
    case duplicateShellCommand

    var title: String {
        switch self {
        case .missingTarget: "卸载残留"
        case .duplicateLabel: "重复标识"
        case .duplicateExecutable: "重复启动目标"
        case .homebrewOverlap: "Homebrew 与 launchd 重叠"
        case .duplicateShellCommand: "重复 Shell 命令"
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

    var id: String { "\(kind.rawValue):\(itemIDs.sorted().joined(separator: "|"))" }
}

enum StartupConflictDetector {
    static func detect(_ items: [StartupItem]) -> [StartupFinding] {
        var findings = residualFindings(items)
        findings += groupedFindings(items, key: { $0.label.lowercased() }) { key, group in
            let sources = Set(group.map(\.source))
            if sources.contains(.homebrewService), !sources.isDisjoint(with: launchdSources) {
                return StartupFinding(
                    kind: .homebrewOverlap,
                    title: key,
                    explanation: "同一服务同时出现在 Homebrew 服务清单与 launchd 配置中；停用前应确认由哪一侧管理。",
                    itemIDs: group.map(\.id)
                )
            }
            return StartupFinding(
                kind: .duplicateLabel,
                title: key,
                explanation: "多个启动来源声明了相同 Label，加载结果可能取决于域、用户或配置覆盖顺序。",
                itemIDs: group.map(\.id)
            )
        }

        findings += groupedFindings(items, key: normalizedExecutable) { path, group in
            StartupFinding(
                kind: .duplicateExecutable,
                title: URL(fileURLWithPath: path).lastPathComponent,
                explanation: "同一执行文件由多个启动项触发，可能造成重复进程或重复工作。",
                itemIDs: group.map(\.id)
            )
        }

        let shellItems = items.filter { $0.source == .shellConfiguration }
        findings += groupedFindings(shellItems, key: normalizedCommand) { command, group in
            StartupFinding(
                kind: .duplicateShellCommand,
                title: String(command.prefix(80)),
                explanation: "相同命令出现在多个 Shell 配置位置，打开终端时可能被重复执行。",
                itemIDs: group.map(\.id)
            )
        }

        return findings.sorted {
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
                explanation: "启动配置仍在，但扫描确认执行目标已缺失；这通常是应用卸载后的残留。",
                itemIDs: [item.id]
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
        return URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
    }

    private static func normalizedCommand(_ item: StartupItem) -> String? {
        guard let command = item.arguments.first else { return nil }
        let normalized = command.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

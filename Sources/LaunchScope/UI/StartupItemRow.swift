import SwiftUI

struct StartupItemRow: View {
    var item: StartupItem
    var isSelected: Bool
    var isTrusted: Bool
    var isNew: Bool
    var riskAssessment: RiskAssessment

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.regularSpacing) {
            AppIconView(item: item)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if item.targetExists == false {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(LaunchScopePalette.warning)
                            .help("执行目标不存在")
                    }
                }

                Text(item.source.compactTitle + " · " + secondaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    StatusBadge(title: item.componentRole, systemImage: "puzzlepiece.extension")
                    if isNew && !isTrusted {
                        StatusBadge(title: "新增", systemImage: "sparkles", color: LaunchScopePalette.warning)
                    } else if isTrusted {
                        StatusBadge(title: "已信任", systemImage: "checkmark.shield", color: LaunchScopePalette.healthy)
                    }
                    riskBadge
                    runtimeBadge
                }
                .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 5)
        .contentShape(Rectangle())
        .background(isSelected ? LaunchScopePalette.selectedFill : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.displayName)，\(item.source.title)，\(riskAssessment.title)，\(item.statusTitle)，签名 \(item.signature.kind.title)")
        .accessibilityHint("打开项目详情")
    }

    private var riskBadge: some View {
        let color: Color = switch riskAssessment.level {
        case .low: .secondary
        case .medium: LaunchScopePalette.warning
        case .high: .red
        }
        return StatusBadge(
            title: riskAssessment.title,
            systemImage: riskAssessment.systemImage,
            color: color
        )
        .help(riskAssessment.reasons.joined(separator: "\n"))
    }

    private var secondaryText: String {
        if item.displayName != item.label { return item.label }
        return item.executablePath ?? item.sourcePath ?? item.label
    }

    private var runtimeBadge: some View {
        let color: Color = switch item.source {
        case .backgroundTask, .loginItem:
            item.isEnabled == true ? LaunchScopePalette.healthy : .secondary
        case .cron, .shellConfiguration:
            .secondary
        default:
            switch item.runtime.state {
            case .running: LaunchScopePalette.healthy
            case .disabled, .notLoaded, .loaded, .unknown: .secondary
            }
        }
        return StatusBadge(title: item.statusTitle, systemImage: statusSystemImage, color: color)
    }

    private var statusSystemImage: String {
        switch item.source {
        case .backgroundTask, .loginItem:
            item.isEnabled == true ? "checkmark.circle.fill" : "minus.circle"
        case .cron, .shellConfiguration:
            "checkmark.circle"
        default:
            "circle.fill"
        }
    }

}

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

                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    if isNew && !isTrusted {
                        StatusBadge(title: "新增未信任", systemImage: "sparkles", color: LaunchScopePalette.warning)
                    } else if isTrusted {
                        StatusBadge(title: "已信任", systemImage: "checkmark.shield", color: LaunchScopePalette.healthy)
                    }
                    StatusBadge(title: item.source.compactTitle, systemImage: item.source.systemImage)
                    riskBadge
                    runtimeBadge
                    signatureBadge
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
    }

    private var riskBadge: some View {
        let color: Color = switch riskAssessment.level {
        case .low: LaunchScopePalette.healthy
        case .medium: LaunchScopePalette.warning
        case .high: .red
        }
        return StatusBadge(
            title: riskAssessment.level.title,
            systemImage: riskAssessment.level.systemImage,
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

    private var signatureBadge: some View {
        let color: Color = switch item.signature.kind {
        case .apple, .developerID, .appStore: LaunchScopePalette.healthy
        case .unsigned, .invalid: LaunchScopePalette.warning
        case .adHoc, .unavailable: .secondary
        }
        return StatusBadge(title: item.signature.kind.title, systemImage: "checkmark.seal", color: color)
    }
}

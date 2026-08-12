import SwiftUI

struct ScanChangesView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.scanChanges.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text(emptyDescription)
                    )
                } else {
                    List {
                        ForEach(ScanChangeKind.allCases, id: \.self) { kind in
                            let changes = store.scanChanges.filter { $0.kind == kind }
                            if !changes.isEmpty {
                                Section("\(kind.title) · \(changes.count)") {
                                    ForEach(changes) { change in
                                        changeRow(change)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    if let comparisonScannedAt = store.comparisonScannedAt {
                        Text("与 \(comparisonScannedAt.formatted(date: .abbreviated, time: .standard)) 的扫描比较")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let error = store.snapshotPersistenceError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
            .navigationTitle("扫描变化")
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
        .frame(minWidth: 700, minHeight: 480)
    }

    private var emptyTitle: String {
        store.comparisonScannedAt == nil ? "已建立扫描基线" : "未检测到变化"
    }

    private var emptyDescription: String {
        store.comparisonScannedAt == nil
            ? "下次扫描会显示新增、移除和关键状态变化。"
            : "与上一次完成的扫描相比，脱敏摘要中的关键状态保持一致。"
    }

    private func changeRow(_ change: ScanChange) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: change.kind.systemImage)
                .foregroundStyle(change.kind.color)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(change.item?.displayName ?? "未知项目").font(.headline)
                HStack(spacing: 8) {
                    Text(change.item?.label ?? "—")
                    Text(change.item?.source.compactTitle ?? "—")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !change.changedFields.isEmpty {
                    Text("变化字段：\(change.changedFields.joined(separator: "、"))")
                        .font(.callout)
                }
                if change.kind == .changed {
                    Text(statusTransition(change))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }

    private func statusTransition(_ change: ScanChange) -> String {
        "\(statusTitle(change.before)) → \(statusTitle(change.after))"
    }

    private func statusTitle(_ item: ScanSnapshotItem?) -> String {
        guard let item else { return "不存在" }
        let allowed = item.isEnabled.map { $0 ? "允许" : "停用" } ?? "允许状态未知"
        let target = item.targetExists.map { $0 ? "目标存在" : "目标缺失" } ?? "目标未知"
        return "\(allowed) · \(item.runtimeState.title) · \(target)"
    }
}

private extension ScanChangeKind {
    var systemImage: String {
        switch self {
        case .added: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        case .changed: "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .added: LaunchScopePalette.healthy
        case .removed: LaunchScopePalette.danger
        case .changed: LaunchScopePalette.warning
        }
    }
}

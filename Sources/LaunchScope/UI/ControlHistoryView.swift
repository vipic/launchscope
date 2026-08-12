import SwiftUI

struct ControlHistoryView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.controlHistory.isEmpty {
                    ContentUnavailableView(
                        "还没有操作记录",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("停用、恢复、停止或启动成功执行后会显示在这里。")
                    )
                } else {
                    List(store.controlHistory) { entry in
                        historyRow(entry)
                    }
                    .listStyle(.inset)
                }
            }
            .safeAreaInset(edge: .top) {
                if let error = store.historyPersistenceError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
            }
            .navigationTitle("操作历史")
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    private func historyRow(_ entry: ControlHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entry.outcome.systemImage)
                .foregroundStyle(entry.outcome.color)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(entry.displayName).font(.headline)
                    Text(entry.action.title).font(.callout.bold())
                    if entry.reversedAt != nil {
                        Text("已撤销")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.label).font(.caption).foregroundStyle(.secondary)
                Text(stateDescription(entry)).font(.callout)
                Text(entry.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(entry.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            if entry.inverseAction != nil {
                Button("撤销") { store.undo(entry) }
                    .disabled(!store.canUndo(entry))
                    .help(store.canUndo(entry) ? "执行反向操作并重新扫描" : "当前状态不允许安全撤销")
            }
        }
        .padding(.vertical, 5)
    }

    private func stateDescription(_ entry: ControlHistoryEntry) -> String {
        let before = stateTitle(entry.before)
        let after = stateTitle(entry.after)
        return "\(before) → \(after)"
    }

    private func stateTitle(_ snapshot: StartupItemStateSnapshot) -> String {
        let allowed = snapshot.isEnabled.map { $0 ? "允许" : "停用" } ?? "允许状态未知"
        let runtime = snapshot.runtimeState?.title ?? "运行状态未知"
        return "\(allowed) · \(runtime)"
    }
}

private extension StartupItemControlOutcome {
    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .partial: "exclamationmark.circle.fill"
        case .failure: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: LaunchScopePalette.healthy
        case .partial: LaunchScopePalette.warning
        case .failure: LaunchScopePalette.danger
        }
    }
}

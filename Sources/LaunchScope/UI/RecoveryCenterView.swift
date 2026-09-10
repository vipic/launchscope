import SwiftUI

struct RecoveryCenterView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var pending: RecoveryCandidate?
    @State private var pendingUndo: ControlHistoryEntry?

    var body: some View {
        NavigationStack {
            List {
                Section("可恢复项目 · \(store.recoveryCandidates.count)") {
                    if store.recoveryCandidates.isEmpty {
                        Text("当前没有可安全恢复的项目").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.recoveryCandidates) { candidate in
                            recoveryRow(candidate)
                        }
                    }
                }
                Section("可撤销操作 · \(store.recoverableHistory.count)") {
                    if store.recoverableHistory.isEmpty {
                        Text("当前没有状态匹配的可撤销操作").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.recoverableHistory) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.safeDisplayName).font(.headline)
                                    Text("\(entry.action.title) · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("撤销") { pendingUndo = entry }
                                    .help("执行与这次操作相反的动作并重新扫描")
                            }
                        }
                    }
                }
                Section("最近操作") {
                    ForEach(store.controlHistory.prefix(20)) { entry in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: UIConstants.compactSpacing) {
                                Text(entry.safeDisplayName).font(.headline)
                                Text("\(entry.source.title) · \(entry.action.title)").font(.callout)
                                Text(entry.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.resultTitle).font(.callout)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: UIConstants.compactSpacing) {
                    Text("可恢复表示当前允许启用，不代表建议启用；恢复前请确认是否仍需要该项目。")
                    if let error = store.historyPersistenceError { Text(error).foregroundStyle(LaunchScopePalette.danger) }
                }.font(.callout).padding(12)
            }
            .navigationTitle("操作记录与恢复")
            .toolbar {
                Button("完成") { dismiss() }
                    .help("关闭操作记录与恢复窗口")
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .accessibilityIdentifier("recovery.center")
        .confirmationDialog(
            pending?.action.confirmationTitle ?? "确认恢复",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            if let pending {
                Button(pending.action.title) {
                    self.pending = nil
                    store.performControl(pending.action, on: pending.item)
                }
                .help("确认执行\(pending.action.title)并重新扫描")
                Button("取消", role: .cancel) { self.pending = nil }
                    .help("保留当前状态，不执行恢复")
            }
        } message: { Text(pending?.action.confirmationMessage ?? "") }
        .confirmationDialog("确认撤销操作", isPresented: Binding(
            get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } }
        ), titleVisibility: .visible) {
            if let entry = pendingUndo {
                Button("执行反向操作") { pendingUndo = nil; store.undo(entry) }
                    .help("执行与原操作相反的动作并重新扫描")
                Button("取消", role: .cancel) { pendingUndo = nil }
                    .help("保留当前状态，不执行撤销")
            }
        } message: {
            Text("\(pendingUndo?.safeDisplayName ?? "")\n\(pendingUndo?.inverseAction?.confirmationMessage ?? "")")
        }
    }

    private func recoveryRow(_ candidate: RecoveryCandidate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.item.displayName).font(.headline)
                Text("\(candidate.item.source.compactTitle) · \(candidate.item.statusTitle)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(candidate.action.title) { pending = candidate }
                .disabled(store.controllingItemID != nil)
                .help("准备\(candidate.action.title)此项目，确认后执行")
        }
    }
}

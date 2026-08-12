import SwiftUI

struct RecoveryCenterView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var pending: RecoveryCandidate?

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
                                    Text(entry.displayName).font(.headline)
                                    Text("\(entry.action.title) · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("撤销") { store.undo(entry) }
                            }
                        }
                    }
                }
                Section("最近操作") {
                    ForEach(store.controlHistory.prefix(20)) { entry in
                        HStack {
                            Text(entry.displayName)
                            Spacer()
                            Text(historyStatus(entry))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("恢复中心")
            .toolbar { Button("完成") { dismiss() } }
        }
        .frame(minWidth: 720, minHeight: 520)
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
                Button("取消", role: .cancel) { self.pending = nil }
            }
        } message: { Text(pending?.action.confirmationMessage ?? "") }
    }

    private func historyStatus(_ entry: ControlHistoryEntry) -> String {
        entry.reversedAt == nil ? entry.action.title : "已撤销"
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
        }
    }
}

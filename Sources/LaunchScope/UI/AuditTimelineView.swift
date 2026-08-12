import SwiftUI

struct AuditTimelineView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var olderIndex = 0
    @State private var newerIndex = 0

    var body: some View {
        NavigationStack {
            Group {
                if store.auditTimeline.isEmpty {
                    ContentUnavailableView(
                        "还没有审计时间线",
                        systemImage: "clock",
                        description: Text("完成扫描后会记录脱敏基线和后续变化。")
                    )
                } else {
                    VStack(spacing: 0) {
                        comparisonBar
                        List(store.auditTimeline) { event in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: event.kind.systemImage)
                                    .frame(width: 24)
                                    .foregroundStyle(event.kind == .removed ? Color.orange : Color.accentColor)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(event.title).font(.headline)
                                        Text(event.kind.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(event.source.title).font(.caption).foregroundStyle(.secondary)
                                    Text(event.subtitle).font(.callout)
                                    Text(event.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("审计时间线")
            .toolbar { Button("完成") { dismiss() } }
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear { newerIndex = max(store.snapshotHistory.count - 1, 0) }
    }

    @ViewBuilder
    private var comparisonBar: some View {
        if store.snapshotHistory.count >= 2 {
            HStack(spacing: 12) {
                Text("比较扫描").font(.callout.bold())
                snapshotPicker("较早", selection: $olderIndex)
                Image(systemName: "arrow.right")
                snapshotPicker("较新", selection: $newerIndex)
                Spacer()
                Text(comparisonSummary).font(.callout).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.bar)
        }
    }

    private func snapshotPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(store.snapshotHistory.indices, id: \.self) { index in
                Text(store.snapshotHistory[index].scannedAt.formatted(date: .abbreviated, time: .shortened))
                    .tag(index)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 180)
    }

    private var comparisonSummary: String {
        guard store.snapshotHistory.indices.contains(olderIndex),
              store.snapshotHistory.indices.contains(newerIndex), olderIndex != newerIndex else {
            return "请选择两个不同扫描点"
        }
        let first = store.snapshotHistory[min(olderIndex, newerIndex)]
        let second = store.snapshotHistory[max(olderIndex, newerIndex)]
        let changes = ScanSnapshotDiff.compare(previous: first, current: second)
        let added = changes.count { $0.kind == .added }
        let removed = changes.count { $0.kind == .removed }
        let changed = changes.count { $0.kind == .changed }
        return "新增 \(added) · 移除 \(removed) · 变化 \(changed)"
    }
}

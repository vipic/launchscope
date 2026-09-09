import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: DashboardStore
    var showChanges: () -> Void
    var showTimeline: () -> Void
    var showRecovery: () -> Void
    var showExport: () -> Void

    private let overviewFilters: [DashboardFilter] = [
        .all, .thirdParty, .untrusted, .highRisk, .findings, .apple, .running, .missingTarget, .disabled, .issues,
    ]

    var body: some View {
        List {
            Section("概览") {
                ForEach(overviewFilters) { filter in
                    sidebarButton(filter)
                }
            }

            Section("审计工具") {
                Button(action: showChanges) { Label("扫描变化（\(store.scanChanges.count)）", systemImage: "arrow.triangle.2.circlepath") }
                Button(action: showTimeline) { Label("审计时间线", systemImage: "clock") }
                Button(action: showRecovery) { Label("恢复中心", systemImage: "lifepreserver") }
                Button(action: showExport) { Label("导出报告", systemImage: "square.and.arrow.up") }
            }.buttonStyle(.plain)

            Section("来源") {
                ForEach(StartupSource.allCases) { source in
                    let filter = DashboardFilter.source(source)
                    if store.count(for: filter) > 0 {
                        sidebarButton(filter)
                    }
                }
            }

            if let scannedAt = store.scannedAt {
                Section("最近扫描") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(scannedAt, format: .dateTime.hour().minute().second())
                        if let duration = store.scanDuration {
                            Text(String(format: "耗时 %.1f 秒", duration))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("系统后台项目") {
                if let updatedAt = store.backgroundTasksUpdatedAt {
                    LabeledContent("后台记录时间") {
                        Text(updatedAt, format: .dateTime.month().day().hour().minute())
                    }
                } else {
                    Text("尚未读取；更新后台记录需授权")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LaunchScope")
        .frame(minWidth: UIConstants.sidebarWidth)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
    }

    private func sidebarButton(_ filter: DashboardFilter) -> some View {
        Button {
            store.selectFilter(filter)
        } label: {
            HStack {
                Label(filter.title, systemImage: filter.systemImage).lineLimit(2)
                Spacer()
                Text(store.count(for: filter), format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(store.selectedFilter == filter ? LaunchScopePalette.selectedFill : Color.clear)
        .accessibilityIdentifier("sidebar.\(filter.id)")
    }
}

import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: DashboardStore
    var showRecovery: () -> Void

    private let overviewFilters: [DashboardFilter] = [
        .thirdParty, .running, .disabled, .issues,
    ]

    private let startupSources: [StartupSource] = [
        .userLaunchAgent, .globalLaunchAgent, .launchDaemon, .backgroundTask, .loginItem, .homebrewService,
    ]

    private let relatedSources: [StartupSource] = [.cron, .shellConfiguration]

    var body: some View {
        List {
            Section("概览") {
                ForEach(overviewFilters) { filter in
                    sidebarButton(filter)
                }
            }

            Section("自启动来源") {
                ForEach(startupSources) { source in
                    let filter = DashboardFilter.source(source)
                    if store.count(for: filter) > 0 {
                        sidebarButton(filter)
                    }
                }
            }

            Section("相关自动任务") {
                ForEach(relatedSources) { source in
                    let filter = DashboardFilter.source(source)
                    if store.count(for: filter) > 0 {
                        sidebarButton(filter)
                    }
                }
            }

            Section("操作") {
                Button(action: showRecovery) {
                    Label("操作记录与恢复", systemImage: "clock.arrow.circlepath")
                }
            }
            .buttonStyle(.plain)

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

            Section("后台记录") {
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

import SwiftUI

struct StartupItemListView: View {
    @ObservedObject var store: DashboardStore
    var items: [StartupItem]
    var groupByOwner: Bool
    @FocusState private var focusedItemID: String?
    @State private var pendingListFocus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.selectedFilter == .thirdParty {
                VStack(alignment: .leading, spacing: UIConstants.compactSpacing) {
                    Text("这台 Mac 的自启动项目").font(.headline)
                    Text("包括系统设置没有完整展示的 LaunchAgent、后台服务和自定义命令。")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(store.backgroundTaskFreshness).font(.callout).foregroundStyle(.secondary)
                }.padding(12)
            }
            if store.isScanning && items.isEmpty {
                ProgressView("正在读取启动来源…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    "没有匹配项目",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("调整筛选条件或清除搜索内容后再试。")
                )
            } else if groupByOwner {
                groupedList
            } else {
                flatList
            }
        }
        .navigationTitle(store.selectedFilter.title)
        .navigationSubtitle(navigationSubtitle)
        .frame(minWidth: UIConstants.listMinimumWidth)
        .navigationSplitViewColumnWidth(min: 400, ideal: 470, max: 620)
        .task(id: store.listFocusRequest) {
            pendingListFocus = true
            focusedItemID = nil
            // List 的行视图在扫描结果发布后才挂载；等待本次布局完成再转移焦点。
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            focusRequestedItem()
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if !ids.contains(store.selectedItemID ?? "") { store.selectedItemID = ids.first }
            if pendingListFocus {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    focusRequestedItem()
                }
            }
        }
        .onChange(of: focusedItemID) { _, itemID in
            guard let itemID else { return }
            if groupByOwner,
               let group = StartupItemListData.groups(for: items).first(where: { $0.id == itemID }) {
                store.selectedItemID = group.items[0].id
            } else if items.contains(where: { $0.id == itemID }) {
                store.selectedItemID = itemID
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if pendingListFocus {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    focusRequestedItem()
                }
            }
        }
    }

    private func focusRequestedItem() {
        guard pendingListFocus, !items.isEmpty, NSApp.isActive else { return }
        if groupByOwner {
            let groups = StartupItemListData.groups(for: items)
            let selectedGroup = items.first(where: { $0.id == store.selectedItemID })?.groupIdentifier
            focusedItemID = groups.contains(where: { $0.id == selectedGroup }) ? selectedGroup : groups.first?.id
        } else {
            focusedItemID = items.contains(where: { $0.id == store.selectedItemID }) ? store.selectedItemID : items.first?.id
        }
        pendingListFocus = false
    }

    private var flatList: some View {
        List(items) { item in
            itemButton(item)
        }
        .listStyle(.inset)
    }

    private var groupedList: some View {
        List {
            ForEach(StartupItemListData.groups(for: items)) { group in
                groupButton(group)
            }
        }
        .listStyle(.inset)
    }

    private var navigationSubtitle: String {
        if groupByOwner {
            let groupCount = StartupItemListData.groups(for: items).count
            return "\(groupCount) 个项目 / \(items.count) 条记录"
        }
        return "\(items.count) 个可见项目 / \(store.count(for: store.selectedFilter)) 个分类项目"
    }

    private func groupButton(_ group: StartupItemGroup) -> some View {
        let representative = group.items[0]
        let isSelected = group.items.contains { $0.id == store.selectedItemID }
        return Button {
            store.selectedItemID = representative.id
        } label: {
            HStack(alignment: .top, spacing: UIConstants.regularSpacing) {
                AppIconView(item: representative)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(group.items.count) 条记录 · \(group.enabledCount) 条启用")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(group.roleSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        StatusBadge(
                            title: group.statusSummary,
                            systemImage: group.statusSystemImage
                        )
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
            .background(isSelected ? LaunchScopePalette.selectedFill : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(group.name)，\(group.items.count) 条记录，\(group.roleSummary)，\(group.statusSummary)")
            .accessibilityHint("打开详情并查看启动原因、参数和停止方式")
        }
        .buttonStyle(.plain)
        .help("查看 \(group.name) 的启动原因、状态、参数和组件记录")
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("startup-item.\(ScanSnapshotItem(item: representative).key)")
        .focusable()
        .focused($focusedItemID, equals: group.id)
    }

    private func groupRiskTitle(_ group: StartupItemGroup) -> String {
        let assessments = group.items.map(store.riskAssessment)
        if assessments.contains(where: { $0.level == .high }) { return "优先核查" }
        if assessments.contains(where: { $0.level == .medium }) { return "待核实" }
        if assessments.contains(where: { $0.hasUnknownEvidence }) { return "信息不足" }
        return "未见异常"
    }

    private func groupRiskIcon(_ group: StartupItemGroup) -> String {
        switch groupRiskTitle(group) {
        case "优先核查": return "exclamationmark.octagon.fill"
        case "待核实": return "exclamationmark.triangle.fill"
        case "信息不足": return "questionmark.circle"
        default: return "checkmark.circle"
        }
    }

    private func groupRiskColor(_ group: StartupItemGroup) -> Color {
        switch groupRiskTitle(group) {
        case "优先核查": return .red
        case "待核实": return LaunchScopePalette.warning
        default: return .secondary
        }
    }

    private func itemButton(_ item: StartupItem) -> some View {
        Button {
            store.selectedItemID = item.id
        } label: {
            StartupItemRow(
                item: item,
                isSelected: store.selectedItemID == item.id,
                isTrusted: store.isTrusted(item),
                isNew: store.isNew(item),
                riskAssessment: store.riskAssessment(for: item)
            )
        }
        .buttonStyle(.plain)
        .help("查看 \(item.displayName) 的启动原因、状态、参数和可用操作")
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contextMenu {
            if let path = item.revealableSourcePath {
                Button("在 Finder 中显示配置") { reveal(path) }
                    .help("在 Finder 中定位此项目的配置文件")
            }
            if let path = item.executablePath {
                Button("在 Finder 中显示执行文件") { reveal(path) }
                    .help("在 Finder 中定位此项目实际运行的文件")
            }
            Button("复制标识") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.label, forType: .string)
            }
            .help("将此启动项的标识复制到剪贴板")
        }
        .accessibilityIdentifier("startup-item.\(ScanSnapshotItem(item: item).key)")
        .focusable()
        .focused($focusedItemID, equals: item.id)
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

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
                    Text("先看值得核查的项目").font(.headline)
                    Text("发现是线索，不是故障或恶意软件判定。")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("待核查 \(store.count(for: .highRisk))") { store.selectFilter(.highRisk) }
                        Button("发现 \(store.count(for: .findings))") { store.selectFilter(.findings) }
                    }.buttonStyle(.bordered)
                    Text(store.backgroundTaskFreshness).font(.callout).foregroundStyle(.secondary)
                }.padding(12)
            } else if store.selectedFilter == .untrusted {
                Text("尚未确认表示你还没有标记信任，不代表项目可疑。")
                    .font(.callout).foregroundStyle(.secondary).padding(12)
            } else if store.selectedFilter == .highRisk {
                Text("仅列出第三方待核查线索；正常启动条件和未知信息不会单独触发。")
                    .font(.callout).foregroundStyle(.secondary).padding(12)
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
            if let itemID { store.selectedItemID = itemID }
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
            let selectedGroup = items.first(where: { $0.id == store.selectedItemID })?.groupName
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
            return "\(groupCount) 个应用 / \(items.count) 个组件"
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
                    Text("\(group.items.count) 个组件 · \(group.enabledCount) 个启用")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(group.roleSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        StatusBadge(title: "已合并", systemImage: "square.stack.3d.up")
                        StatusBadge(title: groupRiskTitle(group), systemImage: groupRiskIcon(group), color: groupRiskColor(group))
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
            .accessibilityLabel("\(group.name)，\(group.items.count) 个组件，\(group.roleSummary)")
            .accessibilityHint("打开应用详情并查看全部组件")
        }
        .buttonStyle(.plain)
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
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contextMenu {
            if let path = item.revealableSourcePath {
                Button("在 Finder 中显示配置") { reveal(path) }
            }
            if let path = item.executablePath {
                Button("在 Finder 中显示执行文件") { reveal(path) }
            }
            Button("复制标识") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.label, forType: .string)
            }
        }
        .accessibilityIdentifier("startup-item.\(ScanSnapshotItem(item: item).key)")
        .focusable()
        .focused($focusedItemID, equals: item.id)
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

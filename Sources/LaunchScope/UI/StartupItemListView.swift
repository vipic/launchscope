import SwiftUI

struct StartupItemListView: View {
    @ObservedObject var store: DashboardStore
    var items: [StartupItem]
    var groupByOwner: Bool

    var body: some View {
        Group {
            if items.isEmpty {
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
        .navigationSubtitle("\(items.count) 个项目")
        .frame(minWidth: UIConstants.listMinimumWidth)
        .navigationSplitViewColumnWidth(min: 400, ideal: 470, max: 620)
    }

    private var flatList: some View {
        List(items) { item in
            itemButton(item)
        }
        .listStyle(.inset)
    }

    private var groupedList: some View {
        List {
            ForEach(groupedItems, id: \.name) { group in
                Section {
                    ForEach(group.items) { item in itemButton(item) }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text(group.items.count, format: .number)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var groupedItems: [(name: String, items: [StartupItem])] {
        Dictionary(grouping: items, by: \.groupName)
            .map { (name: $0.key, items: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
        .accessibilityIdentifier("startup-item.\(item.id)")
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

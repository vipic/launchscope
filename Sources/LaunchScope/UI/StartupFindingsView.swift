import SwiftUI

struct StartupFindingsView: View {
    @ObservedObject var store: DashboardStore
    @FocusState private var focusedFindingID: String?

    var body: some View {
        Group {
            if store.findings.isEmpty {
                ContentUnavailableView(
                    "没有发现冲突或残留",
                    systemImage: "checkmark.circle",
                    description: Text("当前启动来源之间没有明显重复，且已知执行目标均存在。")
                )
            } else {
                List(store.findings) { finding in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(finding.kind.title, systemImage: finding.kind.systemImage)
                            .font(.headline)
                        Text(finding.title).font(.callout.bold()).textSelection(.enabled)
                        Text(finding.explanation).font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Text("涉及 \(finding.itemIDs.count) 个项目")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let item = finding.itemIDs.compactMap({ id in store.items.first { $0.id == id } }).first {
                                Button("查看项目") {
                                    store.selectedFilter = .all
                                    store.selectedItemID = item.id
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .focusable()
                    .focused($focusedFindingID, equals: finding.id)
                    .accessibilityIdentifier("finding.\(finding.id)")
                }
                .navigationTitle("冲突与残留")
            }
        }
        .navigationSplitViewColumnWidth(min: 400, ideal: 470, max: 620)
        .task(id: store.listFocusRequest) {
            await Task.yield()
            focusedFindingID = store.findings.first?.id
        }
    }
}

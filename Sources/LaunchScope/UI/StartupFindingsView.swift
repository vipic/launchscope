import SwiftUI

struct StartupFindingsView: View {
    @ObservedObject var store: DashboardStore
    @FocusState private var focusedFindingID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.regularSpacing) {
            VStack(alignment: .leading, spacing: UIConstants.compactSpacing) {
                Text("先核查线索，再决定是否处理").font(.headline)
                Text("\(store.count(for: .findings)) 条待核实 · \(store.findings.count - store.count(for: .findings)) 条关联与系统参考；不是故障数量。")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("包括多来源关联与系统参考", isOn: $store.includeReferenceFindings)
                    .accessibilityIdentifier("findings.references")
            }.padding(12)
            if store.visibleFindings.isEmpty {
                ContentUnavailableView(
                    "没有匹配的待核实线索",
                    systemImage: "checkmark.circle",
                    description: Text("可以清除搜索或展开关联记录。未知或未扫描的数据不代表已确认正常。")
                )
            } else {
                List(store.visibleFindings) { finding in
                    Button {
                        store.selectFinding(finding)
                    } label: {
                        HStack(alignment: .top, spacing: UIConstants.regularSpacing) {
                            Image(systemName: finding.kind.systemImage)
                                .font(.title3)
                                .foregroundStyle(LaunchScopePalette.warning)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(finding.category.title + " · " + finding.kind.title)
                                    .font(.headline)
                                Text(finding.title)
                                    .font(.callout.bold())
                                    .lineLimit(1)
                                Text(finding.explanation)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text(itemCountText(finding))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 5)
                        .contentShape(Rectangle())
                        .background(store.selectedFindingID == finding.id ? LaunchScopePalette.selectedFill : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .focusable()
                    .focused($focusedFindingID, equals: finding.id)
                    .accessibilityLabel("\(finding.kind.title)，\(finding.title)，\(itemCountText(finding))")
                    .accessibilityHint("打开发现详情")
                    .accessibilityIdentifier("finding.\(finding.id)")
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("发现与关联")
        .navigationSubtitle("\(store.visibleFindings.count) 条记录")
        .frame(minWidth: UIConstants.listMinimumWidth)
        .navigationSplitViewColumnWidth(min: 400, ideal: 470, max: 620)
        .task(id: store.listFocusRequest) {
            await Task.yield()
            focusedFindingID = store.visibleFindings.first?.id
        }
        .onChange(of: store.visibleFindings.map(\.id)) { _, ids in
            if !ids.contains(store.selectedFindingID ?? "") {
                store.selectedFindingID = ids.first
            }
        }
        .onChange(of: focusedFindingID) { _, findingID in
            guard let findingID,
                  let finding = store.findings.first(where: { $0.id == findingID }) else { return }
            store.selectFinding(finding)
        }
    }

    private func itemCountText(_ finding: StartupFinding) -> String {
        finding.itemIDs.count == 1 ? "涉及 1 个项目" : "涉及 \(finding.itemIDs.count) 个项目"
    }
}

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
                    Button {
                        store.selectFinding(finding)
                    } label: {
                        HStack(alignment: .top, spacing: UIConstants.regularSpacing) {
                            Image(systemName: finding.kind.systemImage)
                                .font(.title3)
                                .foregroundStyle(LaunchScopePalette.warning)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(finding.kind.title)
                                    .font(.headline)
                                Text(finding.title)
                                    .font(.callout.bold())
                                    .lineLimit(1)
                                Text(finding.explanation)
                                    .font(.caption)
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
                .navigationTitle("冲突与残留")
                .navigationSubtitle("\(store.findings.count) 条发现")
            }
        }
        .frame(minWidth: UIConstants.listMinimumWidth)
        .navigationSplitViewColumnWidth(min: 400, ideal: 470, max: 620)
        .task(id: store.listFocusRequest) {
            await Task.yield()
            focusedFindingID = store.selectedFindingID ?? store.findings.first?.id
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

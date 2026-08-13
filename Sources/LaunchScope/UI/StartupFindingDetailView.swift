import SwiftUI

struct StartupFindingDetailView: View {
    @ObservedObject var store: DashboardStore
    var finding: StartupFinding?

    var body: some View {
        Group {
            if let finding {
                ScrollView {
                    VStack(alignment: .leading, spacing: UIConstants.sectionSpacing) {
                        header(finding)
                        explanationSection(finding)
                        affectedItemsSection(finding)
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView("选择一条发现", systemImage: "arrow.triangle.branch")
            }
        }
        .frame(minWidth: UIConstants.detailMinimumWidth)
        .navigationSplitViewColumnWidth(min: 420, ideal: 580)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func header(_ finding: StartupFinding) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: finding.kind.systemImage)
                .font(.title)
                .foregroundStyle(LaunchScopePalette.warning)
                .frame(width: UIConstants.largeIconSize, height: UIConstants.largeIconSize)
                .background(LaunchScopePalette.secondaryFill)
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(finding.kind.title)
                    .font(.title2.bold())
                Text(finding.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(summary(finding))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func explanationSection(_ finding: StartupFinding) -> some View {
        FindingDetailSection(title: "判断依据", systemImage: "lightbulb") {
            Text(finding.explanation)
                .font(.callout)
                .textSelection(.enabled)
            Text(guidance(finding))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func affectedItemsSection(_ finding: StartupFinding) -> some View {
        FindingDetailSection(
            title: finding.itemIDs.count == 1 ? "相关项目" : "相关项目对比",
            systemImage: finding.itemIDs.count == 1 ? "doc.text.magnifyingglass" : "rectangle.2.swap"
        ) {
            let items = relatedItems(finding)
            if items.isEmpty {
                Text("相关项目已不在本次扫描结果中，请重新扫描。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    affectedItem(item)
                }
            }
        }
    }

    private func affectedItem(_ item: StartupItem) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.regularSpacing) {
            HStack(spacing: UIConstants.regularSpacing) {
                AppIconView(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                StatusBadge(title: item.source.compactTitle, systemImage: item.source.systemImage)
            }

            FindingDetailRow(label: "当前状态", value: item.statusTitle)
            FindingDetailRow(label: "配置路径", value: item.sourcePath)
            FindingDetailRow(label: "执行文件", value: item.executablePath)

            HStack(spacing: UIConstants.regularSpacing) {
                Button("查看完整详情") { store.showItem(item) }
                if let path = item.revealableSourcePath {
                    Button("显示配置") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func relatedItems(_ finding: StartupFinding) -> [StartupItem] {
        finding.itemIDs.compactMap { id in store.items.first { $0.id == id } }
    }

    private func summary(_ finding: StartupFinding) -> String {
        finding.itemIDs.count == 1 ? "涉及 1 个项目" : "涉及 \(finding.itemIDs.count) 个项目"
    }

    private func guidance(_ finding: StartupFinding) -> String {
        if finding.kind == .missingTarget {
            return "请先核对配置来源与所属应用。LaunchScope 只提供只读证据，不会自动删除残留配置。"
        }
        return "请比较各项目的来源、状态和配置路径，确认应由哪一侧负责启动；LaunchScope 不会自动选择或停用其中任何项目。"
    }
}

private struct FindingDetailSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.regularSpacing) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            VStack(alignment: .leading, spacing: UIConstants.regularSpacing) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LaunchScopePalette.secondaryFill)
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous))
        }
    }
}

private struct FindingDetailRow: View {
    var label: String
    var value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

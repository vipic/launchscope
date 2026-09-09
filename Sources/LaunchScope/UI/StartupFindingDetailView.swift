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
                        if relatedItems(finding).contains(where: { [.backgroundTask, .loginItem].contains($0.source) }) {
                            Text(store.backgroundTaskFreshness).font(.callout).foregroundStyle(.secondary)
                        }
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
                Text(finding.category.title + " · " + finding.kind.title)
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
            FindingDetailRow(label: "组件角色", value: item.componentRole)
            FindingDetailRow(label: "功能提示", value: item.componentNeedHint)
            FindingDetailRow(label: "加载域", value: item.runtime.domain ?? "未知 / 不适用")
            FindingDetailRow(label: "启动条件", value: item.scheduleDescription ?? item.keepAliveDescription ?? item.runAtLoad.map { $0 ? "加载时运行" : "按需触发" } ?? "未知")
            FindingDetailRow(label: "参数", value: item.arguments.isEmpty ? "未提供" : "已隐藏；在完整详情中核对")
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
        if finding.category == .system { return "这些是 Apple 系统参考记录，通常无需处理。共用执行文件本身不是故障证据。" }
        if finding.category == .related { return "这是一组关联记录，不计入待核实数量。优先通过所属应用或 Homebrew 管理，并确认操作影响范围。" }
        return "先核对加载域、参数与启动条件；只有确认同一工作被重复触发后，再从完整详情选择可恢复的操作。"
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

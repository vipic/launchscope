import SwiftUI

struct StartupItemDetailView: View {
    var item: StartupItem?
    var showSensitiveValues: Bool

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: UIConstants.sectionSpacing) {
                        header(item)
                        identitySection(item)
                        runtimeSection(item)
                        launchSection(item)
                        signatureSection(item)
                        configurationSection(item)
                        notesSection(item)
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView("选择一个启动项", systemImage: "sidebar.right")
            }
        }
        .frame(minWidth: UIConstants.detailMinimumWidth)
        .navigationSplitViewColumnWidth(min: 420, ideal: 580)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func header(_ item: StartupItem) -> some View {
        HStack(spacing: 13) {
            AppIconView(item: item, size: UIConstants.largeIconSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).font(.title2.bold()).textSelection(.enabled)
                Text(item.label).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
        }
    }

    private func identitySection(_ item: StartupItem) -> some View {
        DetailSection(title: "身份与来源", systemImage: "person.text.rectangle") {
            DetailRow(label: "类型", value: item.source.title)
            DetailRow(label: "配置路径", value: item.sourcePath)
            DetailRow(label: "所属应用", value: item.attribution?.displayName)
            DetailRow(label: "Bundle ID", value: item.attribution?.bundleIdentifier)
            DetailRow(label: "应用路径", value: item.attribution?.bundlePath)
            DetailRow(label: "归因依据", value: item.attribution?.source)
            DetailRow(label: "Apple 项目", value: item.isAppleItem ? "是" : "否")
        }
    }

    private func runtimeSection(_ item: StartupItem) -> some View {
        DetailSection(title: "当前状态", systemImage: "waveform.path.ecg") {
            DetailRow(label: "状态", value: item.runtime.state.title)
            DetailRow(label: "加载域", value: item.runtime.domain)
            DetailRow(label: "PID", value: item.runtime.processIdentifier.map(String.init))
            DetailRow(label: "上次退出码", value: item.runtime.lastExitCode.map(String.init))
            DetailRow(label: "配置启用", value: item.isEnabled.map { $0 ? "是" : "否" })
            DetailRow(label: "执行目标存在", value: item.targetExists.map { $0 ? "是" : "否" })
        }
    }

    private func launchSection(_ item: StartupItem) -> some View {
        DetailSection(title: "启动方式", systemImage: "play.rectangle.on.rectangle") {
            DetailRow(label: "执行文件", value: item.executablePath)
            DetailRow(label: "参数", value: item.arguments.isEmpty ? nil : item.arguments.joined(separator: "\n"))
            DetailRow(label: "工作目录", value: item.workingDirectory)
            DetailRow(label: "加载时运行", value: item.runAtLoad.map { $0 ? "是" : "否" })
            DetailRow(label: "KeepAlive", value: item.keepAliveDescription)
            DetailRow(label: "计划/触发", value: item.scheduleDescription)
        }
    }

    private func signatureSection(_ item: StartupItem) -> some View {
        DetailSection(title: "代码签名", systemImage: "checkmark.seal") {
            DetailRow(label: "类型", value: item.signature.kind.title)
            DetailRow(label: "签名标识", value: item.signature.identifier)
            DetailRow(label: "Team ID", value: item.signature.teamIdentifier)
            DetailRow(label: "证书链", value: item.signature.authorities.isEmpty ? nil : item.signature.authorities.joined(separator: "\n"))
            DetailRow(label: "状态码", value: item.signature.statusCode.map(String.init))
        }
    }

    private func configurationSection(_ item: StartupItem) -> some View {
        DetailSection(title: "原始配置", systemImage: "list.bullet.rectangle") {
            if !item.environment.isEmpty {
                Text("环境变量").font(.caption).foregroundStyle(.secondary)
                ForEach(item.environment.keys.sorted(), id: \.self) { key in
                    DetailRow(label: key, value: visibleValue(item.environment[key], key: key))
                }
                Divider()
            }
            ForEach(item.configuration.keys.sorted(), id: \.self) { key in
                DetailRow(label: key, value: visibleValue(item.configuration[key], key: key))
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ item: StartupItem) -> some View {
        if !item.discoveryNotes.isEmpty {
            DetailSection(title: "提示", systemImage: "info.circle") {
                ForEach(item.discoveryNotes, id: \.self) { note in
                    Text(note).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    private func visibleValue(_ value: String?, key: String) -> String? {
        guard let value else { return nil }
        let sensitiveTerms = ["token", "password", "passwd", "secret", "api_key", "apikey", "authorization"]
        let isSensitive = sensitiveTerms.contains { key.lowercased().contains($0) }
        return isSensitive && !showSensitiveValues ? "••••••••" : value
    }
}

private struct DetailSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.regularSpacing) {
            Label(title, systemImage: systemImage).font(.headline)
            VStack(alignment: .leading, spacing: UIConstants.regularSpacing) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LaunchScopePalette.secondaryFill)
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous))
        }
    }
}

private struct DetailRow: View {
    var label: String
    var value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 92, alignment: .trailing)
                Text(value).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

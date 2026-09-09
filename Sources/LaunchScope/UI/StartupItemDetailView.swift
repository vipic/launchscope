import SwiftUI
import ServiceManagement

struct StartupItemDetailView: View {
    @ObservedObject var store: DashboardStore
    var item: StartupItem?
    var showSensitiveValues: Bool
    @State private var pendingControlAction: StartupItemControlAction?
    @State private var showAnnotationEditor = false

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: UIConstants.sectionSpacing) {
                        header(item)
                        if [.backgroundTask, .loginItem].contains(item.source) {
                            VStack(alignment: .leading, spacing: UIConstants.compactSpacing) {
                                Label("后台记录时效", systemImage: "clock").font(.headline)
                                Text(store.backgroundTaskFreshness).font(.callout)
                                Button("更新后台记录…") { store.refreshBackgroundTasks() }
                                    .disabled(store.isScanning)
                                    .help("macOS 会要求管理员授权")
                            }
                            .padding(12).background(LaunchScopePalette.secondaryFill)
                        }
                        runtimeSection(item)
                        componentSection(item)
                        actionSection(item)
                        riskSection(item)
                        identitySection(item)
                        if item.runtime.processIdentifier != nil { resourceSection(item) }
                        annotationSection(item)
                        launchSection(item)
                        signatureSection(item)
                        DisclosureGroup("查看原始配置") { configurationSection(item) }
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
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingControlAction != nil },
                set: { if !$0 { pendingControlAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item, let action = pendingControlAction {
                Button(action.title, role: action.isDestructive ? .destructive : nil) {
                    pendingControlAction = nil
                    store.performControl(action, on: item)
                }
                .accessibilityIdentifier("confirmation.control")
                Button("取消", role: .cancel) { pendingControlAction = nil }
            }
        } message: {
            Text(confirmationMessage)
        }
        .sheet(isPresented: $showAnnotationEditor) {
            if let item {
                ItemAnnotationEditorView(item: item, annotation: store.annotation(for: item)) { note, tags, trusted in
                    store.saveAnnotation(for: item, note: note, tags: tags, isTrusted: trusted)
                }
            }
        }
    }

    private func resourceSection(_ item: StartupItem) -> some View {
        DetailSection(title: "资源观察", systemImage: "gauge.with.dots.needle.67percent") {
            if let observation = store.resourceObservation(for: item) {
                DetailRow(label: "CPU", value: observation.cpuPercent.formatted(.number.precision(.fractionLength(1))) + "%")
                DetailRow(label: "内存", value: ByteCountFormatter.string(fromByteCount: Int64(observation.residentMemoryBytes), countStyle: .memory))
                DetailRow(label: "运行时长", value: Duration.seconds(observation.elapsedSeconds).formatted(.time(pattern: .hourMinuteSecond)))
                if let date = store.resourcesObservedAt {
                    DetailRow(label: "采样时间", value: date.formatted(date: .omitted, time: .standard))
                }
            } else {
                Text(item.runtime.processIdentifier == nil ? "该项目当前没有可观察的进程。" : "点击工具栏“观察资源”获取一次即时样本。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func annotationSection(_ item: StartupItem) -> some View {
        let annotation = store.annotation(for: item)
        return DetailSection(title: "用户标记", systemImage: "tag") {
            HStack {
                Label(
                    annotation?.isTrusted == true ? "已确认信任" : "尚未确认 · 不代表可疑",
                    systemImage: annotation?.isTrusted == true ? "checkmark.shield.fill" : "shield.lefthalf.filled"
                )
                Spacer()
                Button("编辑") { showAnnotationEditor = true }.buttonStyle(.bordered)
            }
            if let tags = annotation?.tags, !tags.isEmpty {
                DetailRow(label: "标签", value: tags.joined(separator: "、"))
            }
            if let note = annotation?.note, !note.isEmpty {
                DetailRow(label: "备注", value: note)
            }
            if let error = store.annotationPersistenceError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func actionSection(_ item: StartupItem) -> some View {
        let guidance = item.guidance
        return DetailSection(title: "建议操作", systemImage: "wrench.and.screwdriver") {
            VStack(alignment: .leading, spacing: UIConstants.regularSpacing) {
                Text(guidance.title).font(.callout.bold())
                Text(guidance.summary).font(.callout).foregroundStyle(.secondary)

                actionButtons(item, guidance: guidance).buttonStyle(.bordered)

                if store.controllingItemID == item.id {
                    ProgressView("正在执行操作并重新扫描…").controlSize(.small)
                }
            }
        }
    }

    private func actionButtons(_ item: StartupItem, guidance: StartupItemGuidance) -> some View {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)],
                          alignment: .leading, spacing: UIConstants.regularSpacing) {
                    if let action = store.availableControlAction(for: item) {
                        Button(action.title, role: action.isDestructive ? .destructive : nil) {
                            pendingControlAction = action
                        }
                        .disabled(store.controllingItemID != nil)
                        .accessibilityIdentifier("control.\(action.rawValue)")
                    }
                    if guidance.opensLoginItemSettings {
                        Button("打开登录项设置") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                    if let path = item.revealableSourcePath {
                        Button("显示配置") { reveal(path) }
                    }
                    if let path = item.attribution?.bundlePath {
                        Button("显示所属应用") { reveal(path) }
                    }
                    if let command = guidance.diagnosticCommand {
                        Button("复制只读诊断命令") { copy(command) }
                    }
                }
    }

    private var confirmationTitle: String {
        guard let action = pendingControlAction else { return "确认操作" }
        return action.confirmationTitle
    }

    private var confirmationMessage: String {
        guard let action = pendingControlAction else { return "" }
        guard let item else { return action.confirmationMessage }
        switch action {
        case .disableCron, .enableCron, .disableShellLine, .enableShellLine:
            let target = item.sourcePath ?? item.source.title
            let line = item.controlMetadata["line"].map { "第 \($0) 行" } ?? "目标行"
            return "\(action.confirmationMessage)\n\n操作目标：\(target) · \(line)"
        default:
            return action.confirmationMessage
        }
    }

    private func header(_ item: StartupItem) -> some View {
        HStack(spacing: 13) {
            AppIconView(item: item, size: UIConstants.largeIconSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).font(.title2.bold()).textSelection(.enabled)
                Text(item.label).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text(store.riskAssessment(for: item).title)
                    .font(.headline)
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

    private func componentSection(_ item: StartupItem) -> some View {
        let related = store.items.filter { $0.groupName == item.groupName }
        guard related.count > 1 else { return AnyView(EmptyView()) }
        return AnyView(DetailSection(title: "同一应用的其他组件", systemImage: "square.stack.3d.up") {
            Text("这些项目都归属于 \(item.ownerName)。每个组件负责的功能不同，是否需要取决于你是否使用该功能。")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(related) { component in
                HStack(alignment: .top, spacing: UIConstants.regularSpacing) {
                    Image(systemName: component.id == item.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(component.id == item.id ? LaunchScopePalette.accent : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(component.displayName).font(.callout.bold())
                        Text("\(component.componentRole) · \(component.source.compactTitle) · \(component.statusTitle)")
                            .font(.callout).foregroundStyle(.secondary)
                        Text(component.componentNeedHint).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        })
    }

    private func riskSection(_ item: StartupItem) -> some View {
        let assessment = store.riskAssessment(for: item)
        return DetailSection(title: "判断依据", systemImage: assessment.systemImage) {
            DetailRow(label: "结论", value: assessment.title)
            ForEach(Array(assessment.reasons.enumerated()), id: \.offset) { _, reason in
                Label(reason, systemImage: "circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("此结论用于安排核查顺序，不是恶意软件判定；正常启动条件与未知信息不会单独提升等级。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func runtimeSection(_ item: StartupItem) -> some View {
        DetailSection(title: "当前状态", systemImage: "waveform.path.ecg") {
            DetailRow(label: item.statusLabel, value: item.statusTitle)
            DetailRow(label: "加载状态", value: item.runtime.state.title)
            DetailRow(label: "加载域", value: item.runtime.domain)
            DetailRow(label: "PID", value: item.runtime.processIdentifier.map(String.init))
            DetailRow(label: "上次退出码", value: item.runtime.lastExitCode.map(String.init))
            DetailRow(label: "配置启用", value: item.isEnabled.map { $0 ? "是" : "否" } ?? "未知")
            DetailRow(label: "执行目标存在", value: item.targetExists.map { $0 ? "是" : "否" } ?? "未知 · 尚未核实")
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

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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

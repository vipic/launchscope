import SwiftUI
import ServiceManagement

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @AppStorage(PreferenceKeys.hideAppleItems) private var hideAppleItems = true
    @AppStorage(PreferenceKeys.showSensitiveValues) private var showSensitiveValues = false
    @AppStorage(PreferenceKeys.groupByOwner) private var groupByOwner = true
    @AppStorage(PreferenceKeys.hideTrustedItems) private var hideTrustedItems = false
    @State private var showControlHistory = false
    @State private var showScanChanges = false
    @State private var showAuditExport = false
    @State private var showRecoveryCenter = false
    @State private var showPrivilegedHelper = false
    @State private var showAuditTimeline = false
    @StateObject private var privilegedHelper = PrivilegedHelperManager()

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } content: {
            if store.selectedFilter == .issues {
                IssuesView(issues: store.issues)
            } else if store.selectedFilter == .findings {
                StartupFindingsView(store: store)
            } else {
                StartupItemListView(
                    store: store,
                    items: visibleItems,
                    groupByOwner: groupByOwner
                )
            }
        } detail: {
            StartupItemDetailView(
                store: store,
                item: store.selectedItem,
                showSensitiveValues: showSensitiveValues
            )
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索名称、标识、路径或参数")
        .toolbar {
            ToolbarItemGroup {
                if CommandLine.arguments.contains("--release-acceptance") {
                    Menu {
                        acceptanceButton("定位 LaunchAgent", source: .userLaunchAgent, label: "com.nekutai.launchscope.acceptance")
                        acceptanceButton("定位 Homebrew", source: .homebrewService, label: "homebrew.mxcl.launchscope-acceptance")
                        acceptanceButton("定位 Cron", source: .cron, label: "cron.1")
                        acceptanceButton("定位 Shell", source: .shellConfiguration, label: "shell.bashrc.1")
                    } label: {
                        Label("验收定位", systemImage: "scope")
                    }
                    .accessibilityIdentifier("toolbar.acceptance")
                }

                Button {
                    showScanChanges = true
                } label: {
                    Label("扫描变化（\(store.scanChanges.count)）", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("查看与上一次完成扫描之间的脱敏差异")
                .accessibilityIdentifier("toolbar.scan-changes")

                Button {
                    showControlHistory = true
                } label: {
                    Label("操作历史", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("toolbar.control-history")

                Button {
                    showAuditTimeline = true
                } label: {
                    Label("审计时间线", systemImage: "clock")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .accessibilityIdentifier("toolbar.audit-timeline")

                Button {
                    showRecoveryCenter = true
                } label: {
                    Label("恢复中心", systemImage: "lifepreserver")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .accessibilityIdentifier("toolbar.recovery")

                Button {
                    showAuditExport = true
                } label: {
                    Label("导出审计报告", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: .command)
                .accessibilityIdentifier("toolbar.export")

                Menu {
                    Toggle("按所属应用归组", isOn: $groupByOwner)
                    Toggle("隐藏 Apple 项目", isOn: $hideAppleItems)
                    Toggle("隐藏已信任项目", isOn: $hideTrustedItems)
                    Toggle("显示敏感配置值", isOn: $showSensitiveValues)
                    Toggle("新增未信任项目提醒", isOn: Binding(
                        get: { store.notificationsEnabled },
                        set: { store.setNotificationsEnabled($0) }
                    ))
                    .accessibilityIdentifier("settings.notifications")
                    if let error = store.notificationError {
                        Text(error).foregroundStyle(.secondary)
                    }
                    Divider()
                    Button("管理员辅助程序…") { showPrivilegedHelper = true }
                    Button("打开系统登录项设置") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } label: {
                    Label("显示选项", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("toolbar.display-options")

                Button {
                    store.refresh()
                } label: {
                    if store.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(store.isScanning)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityIdentifier("toolbar.refresh")

                Button {
                    store.observeResources()
                } label: {
                    if store.isObservingResources {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("观察资源", systemImage: "gauge.with.dots.needle.67percent")
                    }
                }
                .disabled(store.isObservingResources || store.isScanning)
                .help("对当前运行项目执行一次 ps 即时采样；不会持续后台监控")
                .accessibilityIdentifier("toolbar.observe-resources")

                Button {
                    store.refreshBackgroundTasks()
                } label: {
                    if store.isRefreshingBackgroundTasks {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("更新系统后台项目", systemImage: "rectangle.stack.badge.play")
                    }
                }
                .disabled(store.isScanning)
                .help("运行 sfltool 读取系统后台项目；macOS 会要求管理员授权")
                .accessibilityIdentifier("toolbar.background-tasks")
            }
        }
        .task { store.refreshIfNeeded() }
        .sheet(isPresented: $showControlHistory) {
            ControlHistoryView(store: store)
        }
        .sheet(isPresented: $showAuditTimeline) {
            AuditTimelineView(store: store)
        }
        .sheet(isPresented: $showScanChanges) {
            ScanChangesView(store: store)
        }
        .sheet(isPresented: $showAuditExport) {
            AuditExportView(
                allItems: store.items,
                visibleItems: visibleItems,
                annotations: store.annotations,
                issues: store.issues,
                changes: store.scanChanges,
                scannedAt: store.scannedAt
            )
        }
        .sheet(isPresented: $showRecoveryCenter) {
            RecoveryCenterView(store: store)
        }
        .sheet(isPresented: $showPrivilegedHelper) {
            PrivilegedHelperView(manager: privilegedHelper)
        }
        .alert(item: $store.controlResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("好"))
            )
        }
        .frame(minWidth: 1050, minHeight: 660)
        .accessibilityIdentifier("dashboard.root")
    }

    private var visibleItems: [StartupItem] {
        store.filteredItems(hideAppleItems: hideAppleItems, hideTrustedItems: hideTrustedItems)
    }

    private func acceptanceButton(_ title: String, source: StartupSource, label: String) -> some View {
        Button(title) { store.selectAcceptanceItem(source: source, label: label) }
            .disabled(!store.items.contains { $0.source == source && $0.label == label })
    }
}

import SwiftUI
import ServiceManagement

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @ObservedObject var updateStore: AppUpdateStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PreferenceKeys.hideAppleItems) private var hideAppleItems = true
    @AppStorage(PreferenceKeys.showSensitiveValues) private var showSensitiveValues = false
    @State private var showRecoveryCenter = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                store: store,
                hideAppleItems: hideAppleItems,
                showRecovery: { showRecoveryCenter = true }
            )
        } content: {
            if store.selectedFilter == .issues {
                IssuesView(store: store)
            } else if store.selectedFilter == .findings {
                StartupFindingsView(store: store)
            } else {
                StartupItemListView(
                    store: store,
                    items: visibleItems,
                    groupByOwner: true
                )
            }
        } detail: {
            if store.selectedFilter == .findings {
                StartupFindingDetailView(store: store, finding: store.selectedFinding)
            } else {
                StartupItemDetailView(
                    store: store,
                    item: store.selectedItem,
                    showSensitiveValues: showSensitiveValues
                )
            }
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索名称、标识、路径或参数")
        .toolbar {
            ToolbarItemGroup {
                if CommandLine.arguments.contains("--release-acceptance") {
                    acceptanceButton(
                        "定位 LaunchAgent",
                        identifier: "toolbar.acceptance.launchAgent",
                        source: .userLaunchAgent,
                        label: "com.nekutai.launchscope.acceptance"
                    )
                    acceptanceButton(
                        "定位 Homebrew",
                        identifier: "toolbar.acceptance.homebrew",
                        source: .homebrewService,
                        label: "homebrew.mxcl.launchscope-acceptance"
                    )
                }

                Button {
                    showRecoveryCenter = true
                } label: {
                    Label("操作记录与恢复", systemImage: "clock.arrow.circlepath")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .accessibilityIdentifier("toolbar.recovery")

                Menu {
                    Toggle("显示敏感配置值", isOn: $showSensitiveValues)
                    Button("打开系统登录项设置") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    Divider()
                    Button("LaunchScope 设置…") { openSettings() }
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
        .safeAreaInset(edge: .bottom) {
            if let error = store.notificationError {
                HStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("settings.notification-error")
                    Spacer()
                    Button("关闭") { store.dismissNotificationError() }
                        .accessibilityIdentifier("settings.notification-error-dismiss")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .task {
            store.refreshIfNeeded()
            updateStore.checkAutomaticallyIfNeeded()
        }
        .sheet(isPresented: $showRecoveryCenter) {
            RecoveryCenterView(store: store)
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
        store.filteredItems(hideAppleItems: hideAppleItems, hideTrustedItems: false)
    }

    private func acceptanceButton(
        _ title: String,
        identifier: String,
        source: StartupSource,
        label: String
    ) -> some View {
        Button(title) { store.selectAcceptanceItem(source: source, label: label) }
            .disabled(!store.items.contains { $0.source == source && $0.label == label })
            .accessibilityIdentifier(identifier)
    }
}

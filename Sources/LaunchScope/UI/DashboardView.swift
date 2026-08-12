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

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } content: {
            if store.selectedFilter == .issues {
                IssuesView(issues: store.issues)
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
                Button {
                    showScanChanges = true
                } label: {
                    Label("扫描变化（\(store.scanChanges.count)）", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("查看与上一次完成扫描之间的脱敏差异")

                Button {
                    showControlHistory = true
                } label: {
                    Label("操作历史", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    showRecoveryCenter = true
                } label: {
                    Label("恢复中心", systemImage: "lifepreserver")
                }

                Button {
                    showAuditExport = true
                } label: {
                    Label("导出审计报告", systemImage: "square.and.arrow.up")
                }

                Menu {
                    Toggle("按所属应用归组", isOn: $groupByOwner)
                    Toggle("隐藏 Apple 项目", isOn: $hideAppleItems)
                    Toggle("隐藏已信任项目", isOn: $hideTrustedItems)
                    Toggle("显示敏感配置值", isOn: $showSensitiveValues)
                    Toggle("新增未信任项目提醒", isOn: Binding(
                        get: { store.notificationsEnabled },
                        set: { store.setNotificationsEnabled($0) }
                    ))
                    if let error = store.notificationError {
                        Text(error).foregroundStyle(.secondary)
                    }
                    Divider()
                    Button("打开系统登录项设置") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } label: {
                    Label("显示选项", systemImage: "slider.horizontal.3")
                }

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
            }
        }
        .task { store.refreshIfNeeded() }
        .sheet(isPresented: $showControlHistory) {
            ControlHistoryView(store: store)
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
        .alert(item: $store.controlResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("好"))
            )
        }
        .frame(minWidth: 1050, minHeight: 660)
    }

    private var visibleItems: [StartupItem] {
        store.filteredItems(hideAppleItems: hideAppleItems, hideTrustedItems: hideTrustedItems)
    }
}

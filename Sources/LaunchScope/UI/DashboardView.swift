import SwiftUI
import ServiceManagement

struct DashboardView: View {
    @ObservedObject var store: DashboardStore
    @AppStorage(PreferenceKeys.hideAppleItems) private var hideAppleItems = true
    @AppStorage(PreferenceKeys.showSensitiveValues) private var showSensitiveValues = false
    @AppStorage(PreferenceKeys.groupByOwner) private var groupByOwner = true

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } content: {
            if store.selectedFilter == .issues {
                IssuesView(issues: store.issues)
            } else {
                StartupItemListView(
                    store: store,
                    items: store.filteredItems(hideAppleItems: hideAppleItems),
                    groupByOwner: groupByOwner
                )
            }
        } detail: {
            StartupItemDetailView(item: store.selectedItem, showSensitiveValues: showSensitiveValues)
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索名称、标识、路径或参数")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Toggle("按所属应用归组", isOn: $groupByOwner)
                    Toggle("隐藏 Apple 项目", isOn: $hideAppleItems)
                    Toggle("显示敏感配置值", isOn: $showSensitiveValues)
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
        .frame(minWidth: 1050, minHeight: 660)
    }
}

import SwiftUI

struct PrivilegedHelperView: View {
    @ObservedObject var manager: PrivilegedHelperManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("状态", value: manager.status.title)
                Text("管理员辅助程序仅提供固定的全局启动项控制接口。主应用不会执行 sudo、AppleScript 或任意 root 命令。")
                    .foregroundStyle(.secondary)
                if let message = manager.connectionMessage {
                    Label(message, systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                }
                if let error = manager.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                HStack {
                    Button("注册辅助程序") { manager.register() }
                        .disabled(manager.status == .notFound)
                    Button("打开系统批准设置") { manager.openApprovalSettings() }
                    Button("验证安全连接") { manager.testConnection() }
                        .disabled(manager.status != .enabled)
                }
            }
            .padding(20)
            .navigationTitle("管理员辅助程序")
            .toolbar { Button("完成") { dismiss() } }
        }
        .frame(width: 640, height: 330)
        .onAppear { manager.refreshStatus() }
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AuditExportView: View {
    var allItems: [StartupItem]
    var visibleItems: [StartupItem]
    var annotations: [String: ItemAnnotation]
    var issues: [ScanIssue]
    var changes: [ScanChange]
    var scannedAt: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var exportVisibleOnly = true
    @State private var format: AuditExportFormat = .json
    @State private var includeIssues = true
    @State private var includeChanges = true
    @State private var includeNotes = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("导出脱敏审计报告").font(.title2.bold())
            Form {
                Picker("范围", selection: $exportVisibleOnly) {
                    Text("当前筛选（\(visibleItems.count) 项）").tag(true)
                    Text("全部项目（\(allItems.count) 项）").tag(false)
                }
                Picker("格式", selection: $format) {
                    ForEach(AuditExportFormat.allCases) { Text($0.title).tag($0) }
                }
                Toggle("包含扫描问题摘要", isOn: $includeIssues).disabled(format == .csv)
                Toggle("包含最近变化", isOn: $includeChanges).disabled(format == .csv)
                Toggle("包含用户备注", isOn: $includeNotes).disabled(format == .csv)
            }
            GroupBox("字段预览") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("包含：名称、标识、来源、状态、签名、Apple 归属、信任状态、标签", systemImage: "checkmark.circle")
                    Label("默认排除：路径、参数、环境变量、原始配置、PID、证书链", systemImage: "eye.slash")
                    Text(format == .csv ? "CSV 仅导出项目表；问题摘要和变化仅在 JSON 中提供。" : "扫描问题只保留严重级别和脱敏后的来源类别。")
                        .foregroundStyle(.secondary)
                }.font(.callout).padding(6)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("选择位置并导出") { save() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 620)
        .accessibilityIdentifier("export.panel")
    }

    private func save() {
        do {
            let options = AuditExportOptions(
                includeIssues: includeIssues,
                includeChanges: includeChanges,
                includeNotes: includeNotes
            )
            let data = try AuditExporter.data(
                format: format,
                items: exportVisibleOnly ? visibleItems : allItems,
                annotations: annotations,
                issues: issues,
                changes: changes,
                scannedAt: scannedAt,
                options: options
            )
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "LaunchScope-审计报告.\(format.fileExtension)"
            panel.allowedContentTypes = format == .json ? [.json] : [.commaSeparatedText]
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                    dismiss()
                } catch {
                    errorMessage = "无法写入报告：\(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = "无法生成报告：\(error.localizedDescription)"
        }
    }
}

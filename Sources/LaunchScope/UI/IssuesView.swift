import SwiftUI

struct IssuesView: View {
    var issues: [ScanIssue]

    var body: some View {
        Group {
            if issues.isEmpty {
                ContentUnavailableView("没有扫描提示", systemImage: "checkmark.circle")
            } else {
                List(issues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: issue.severity))
                            .foregroundStyle(color(for: issue.severity))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.source).font(.headline).textSelection(.enabled)
                            Text(issue.message).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .navigationTitle("扫描提示")
            }
        }
        .navigationSplitViewColumnWidth(min: 400, ideal: 470, max: 620)
    }

    private func icon(for severity: ScanSeverity) -> String {
        switch severity {
        case .information: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private func color(for severity: ScanSeverity) -> Color {
        switch severity {
        case .information: .blue
        case .warning: LaunchScopePalette.warning
        case .error: LaunchScopePalette.danger
        }
    }
}

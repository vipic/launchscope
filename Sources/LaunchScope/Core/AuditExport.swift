import Foundation

enum AuditExportFormat: String, CaseIterable, Identifiable {
    case json
    case csv
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }
}

struct AuditExportOptions {
    var includeIssues = true
    var includeChanges = true
    var includeNotes = false
}

struct AuditExportDocument: Codable {
    var schemaVersion = 1
    var exportedAt: Date
    var scannedAt: Date?
    var items: [AuditExportItem]
    var issues: [AuditExportIssue]
    var changes: [AuditExportChange]
}

struct AuditExportItem: Codable, Equatable {
    var name: String
    var label: String
    var source: String
    var status: String
    var signature: String
    var isAppleItem: Bool
    var isTrusted: Bool
    var tags: [String]
    var note: String?
}

struct AuditExportIssue: Codable, Equatable {
    var severity: String
    var sourceCategory: String
}

struct AuditExportChange: Codable, Equatable {
    var kind: String
    var name: String
    var source: String
    var changedFields: [String]
}

enum AuditExporter {
    static func data(
        format: AuditExportFormat,
        items: [StartupItem],
        annotations: [String: ItemAnnotation],
        issues: [ScanIssue],
        changes: [ScanChange],
        scannedAt: Date?,
        options: AuditExportOptions
    ) throws -> Data {
        let safeItems = items.map { item in
            let annotation = annotations[item.privacySafeKey]
            return AuditExportItem(
                name: item.source == .cron ? "Cron 任务" : item.displayName,
                label: item.source == .cron ? "（已脱敏）" : item.label,
                source: item.source.title,
                status: item.statusTitle,
                signature: item.signature.kind.title,
                isAppleItem: item.isAppleItem,
                isTrusted: annotation?.isTrusted ?? false,
                tags: annotation?.tags ?? [],
                note: options.includeNotes ? annotation?.note : nil
            )
        }

        switch format {
        case .json:
            let document = AuditExportDocument(
                exportedAt: Date(),
                scannedAt: scannedAt,
                items: safeItems,
                issues: options.includeIssues ? issues.map(safeIssue) : [],
                changes: options.includeChanges ? changes.compactMap(safeChange) : []
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(document)
        case .csv:
            var rows = [["名称", "标识", "来源", "状态", "签名", "Apple 项目", "已信任", "标签"]]
            rows += safeItems.map {
                [$0.name, $0.label, $0.source, $0.status, $0.signature,
                 $0.isAppleItem ? "是" : "否", $0.isTrusted ? "是" : "否", $0.tags.joined(separator: "|")]
            }
            return Data(rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\n").utf8)
        }
    }

    private static func safeIssue(_ issue: ScanIssue) -> AuditExportIssue {
        let category = issue.source.hasPrefix("/") ? "文件来源" : issue.source
        return AuditExportIssue(severity: issue.severity.rawValue, sourceCategory: category)
    }

    private static func safeChange(_ change: ScanChange) -> AuditExportChange? {
        guard let item = change.item else { return nil }
        return AuditExportChange(
            kind: change.kind.title,
            name: item.displayName,
            source: item.source.title,
            changedFields: change.changedFields
        )
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

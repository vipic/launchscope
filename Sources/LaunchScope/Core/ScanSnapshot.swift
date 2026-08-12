import CryptoKit
import Foundation

struct ScanSnapshotItem: Codable, Equatable, Sendable {
    var key: String
    var label: String
    var displayName: String
    var source: StartupSource
    var isEnabled: Bool?
    var runtimeState: RuntimeState
    var targetExists: Bool?
    var signatureKind: SignatureKind
    var isAppleItem: Bool

    init(item: StartupItem) {
        key = Self.hash(item.id)
        label = item.label
        displayName = item.source == .cron ? "Cron 任务" : item.displayName
        source = item.source
        isEnabled = item.isEnabled
        runtimeState = item.runtime.state
        targetExists = item.targetExists
        signatureKind = item.signature.kind
        isAppleItem = item.isAppleItem
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ScanSnapshot: Codable, Equatable, Sendable {
    var scannedAt: Date
    var items: [ScanSnapshotItem]

    init(report: ScanReport) {
        scannedAt = report.scannedAt
        items = report.items.map(ScanSnapshotItem.init)
    }
}

enum ScanChangeKind: String, CaseIterable, Sendable {
    case added
    case removed
    case changed

    var title: String {
        switch self {
        case .added: "新增"
        case .removed: "移除"
        case .changed: "状态变化"
        }
    }
}

struct ScanChange: Identifiable, Equatable, Sendable {
    var kind: ScanChangeKind
    var before: ScanSnapshotItem?
    var after: ScanSnapshotItem?
    var changedFields: [String]

    var id: String {
        "\(kind.rawValue):\((after ?? before)?.key ?? "unknown")"
    }

    var item: ScanSnapshotItem? { after ?? before }
}

enum ScanSnapshotDiff {
    static func compare(previous: ScanSnapshot, current: ScanSnapshot) -> [ScanChange] {
        let previousByKey = Dictionary(uniqueKeysWithValues: previous.items.map { ($0.key, $0) })
        let currentByKey = Dictionary(uniqueKeysWithValues: current.items.map { ($0.key, $0) })
        let allKeys = Set(previousByKey.keys).union(currentByKey.keys)

        return allKeys.compactMap { key -> ScanChange? in
            let before = previousByKey[key]
            let after = currentByKey[key]
            switch (before, after) {
            case (nil, let after?):
                return ScanChange(kind: .added, before: nil, after: after, changedFields: [])
            case (let before?, nil):
                return ScanChange(kind: .removed, before: before, after: nil, changedFields: [])
            case (let before?, let after?):
                let fields = changedFields(before: before, after: after)
                guard !fields.isEmpty else { return nil }
                return ScanChange(kind: .changed, before: before, after: after, changedFields: fields)
            case (nil, nil):
                return nil
            }
        }.sorted {
            let lhsKind = ScanChangeKind.allCases.firstIndex(of: $0.kind) ?? 0
            let rhsKind = ScanChangeKind.allCases.firstIndex(of: $1.kind) ?? 0
            if lhsKind != rhsKind { return lhsKind < rhsKind }
            return ($0.item?.displayName ?? "").localizedStandardCompare($1.item?.displayName ?? "") == .orderedAscending
        }
    }

    private static func changedFields(before: ScanSnapshotItem, after: ScanSnapshotItem) -> [String] {
        var fields: [String] = []
        if before.displayName != after.displayName { fields.append("名称") }
        if before.isEnabled != after.isEnabled { fields.append("允许状态") }
        if before.runtimeState != after.runtimeState { fields.append("运行状态") }
        if before.targetExists != after.targetExists { fields.append("执行目标") }
        if before.signatureKind != after.signatureKind { fields.append("代码签名") }
        if before.isAppleItem != after.isAppleItem { fields.append("Apple 归属") }
        return fields
    }
}

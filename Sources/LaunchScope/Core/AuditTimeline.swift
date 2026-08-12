import Foundation

enum AuditTimelineEventKind: String, Sendable {
    case firstSeen
    case removed
    case changed
    case control

    var title: String {
        switch self {
        case .firstSeen: "首次发现"
        case .removed: "扫描中移除"
        case .changed: "状态变化"
        case .control: "用户操作"
        }
    }

    var systemImage: String {
        switch self {
        case .firstSeen: "sparkles"
        case .removed: "minus.circle"
        case .changed: "arrow.triangle.2.circlepath"
        case .control: "hand.tap"
        }
    }
}

struct AuditTimelineEvent: Identifiable, Equatable, Sendable {
    var id: String
    var timestamp: Date
    var kind: AuditTimelineEventKind
    var title: String
    var subtitle: String
    var source: StartupSource
}

enum AuditTimeline {
    static func build(
        snapshots: [ScanSnapshot],
        controlHistory: [ControlHistoryEntry]
    ) -> [AuditTimelineEvent] {
        let ordered = snapshots.sorted { $0.scannedAt < $1.scannedAt }
        var events: [AuditTimelineEvent] = []

        if let first = ordered.first {
            events += first.items.map { item in
                event(
                    id: "baseline:\(item.key)", timestamp: first.scannedAt, kind: .firstSeen,
                    item: item, subtitle: "建立首个审计基线"
                )
            }
        }

        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            events += ScanSnapshotDiff.compare(previous: previous, current: current).compactMap { change in
                guard let item = change.item else { return nil }
                switch change.kind {
                case .added:
                    return event(
                        id: "scan:\(current.scannedAt.timeIntervalSince1970):\(change.id)",
                        timestamp: current.scannedAt, kind: .firstSeen, item: item,
                        subtitle: "相较上一次扫描新增"
                    )
                case .removed:
                    return event(
                        id: "scan:\(current.scannedAt.timeIntervalSince1970):\(change.id)",
                        timestamp: current.scannedAt, kind: .removed, item: item,
                        subtitle: "相较上一次扫描已不再出现"
                    )
                case .changed:
                    return event(
                        id: "scan:\(current.scannedAt.timeIntervalSince1970):\(change.id)",
                        timestamp: current.scannedAt, kind: .changed, item: item,
                        subtitle: change.changedFields.joined(separator: "、")
                    )
                }
            }
        }

        events += controlHistory.map { entry in
            AuditTimelineEvent(
                id: "control:\(entry.id.uuidString)", timestamp: entry.timestamp, kind: .control,
                title: entry.displayName,
                subtitle: "\(entry.action.title) · \(entry.outcome.title)", source: entry.source
            )
        }
        return events.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
            return $0.id < $1.id
        }
    }

    private static func event(
        id: String, timestamp: Date, kind: AuditTimelineEventKind,
        item: ScanSnapshotItem, subtitle: String
    ) -> AuditTimelineEvent {
        AuditTimelineEvent(
            id: id, timestamp: timestamp, kind: kind,
            title: item.displayName, subtitle: subtitle, source: item.source
        )
    }
}

private extension StartupItemControlOutcome {
    var title: String {
        switch self {
        case .success: "成功"
        case .partial: "部分成功"
        case .failure: "失败"
        }
    }
}

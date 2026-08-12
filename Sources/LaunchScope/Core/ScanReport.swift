import Foundation

enum ScanSeverity: String, Codable, Sendable {
    case information
    case warning
    case error
}

struct ScanIssue: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var source: String
    var message: String
    var severity: ScanSeverity
}

struct ScanReport: Sendable {
    var items: [StartupItem]
    var issues: [ScanIssue]
    var scannedAt: Date
    var duration: TimeInterval
    var backgroundTasksUpdatedAt: Date?
}

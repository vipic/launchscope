import Foundation

struct NotificationLedger: Codable, Equatable, Sendable {
    var activeChangeIDs: Set<String> = []
}

protocol NotificationLedgerPersisting: Sendable {
    func load() throws -> NotificationLedger
    func save(_ ledger: NotificationLedger) throws
}

struct NotificationLedgerPersistence: NotificationLedgerPersisting, Sendable {
    var fileURL: URL

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? base
            .appendingPathComponent("LaunchScope", isDirectory: true)
            .appendingPathComponent("notification-ledger.json")
    }

    func load() throws -> NotificationLedger {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return NotificationLedger() }
        return try JSONDecoder().decode(NotificationLedger.self, from: Data(contentsOf: fileURL))
    }

    func save(_ ledger: NotificationLedger) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ledger).write(to: fileURL, options: .atomic)
    }
}

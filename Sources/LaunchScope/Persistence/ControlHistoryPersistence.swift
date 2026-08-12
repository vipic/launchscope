import Foundation

protocol ControlHistoryPersisting: Sendable {
    func load() throws -> [ControlHistoryEntry]
    func save(_ entries: [ControlHistoryEntry]) throws
}

struct ControlHistoryPersistence: ControlHistoryPersisting, Sendable {
    var fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base
                .appendingPathComponent("LaunchScope", isDirectory: true)
                .appendingPathComponent("control-history.json")
        }
    }

    func load() throws -> [ControlHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.historyDecoder.decode([ControlHistoryEntry].self, from: data)
    }

    func save(_ entries: [ControlHistoryEntry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.historyEncoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var historyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var historyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

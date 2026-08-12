import Foundation

protocol ScanSnapshotPersisting: Sendable {
    func load() throws -> ScanSnapshot?
    func save(_ snapshot: ScanSnapshot) throws
}

struct ScanSnapshotPersistence: ScanSnapshotPersisting, Sendable {
    var fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base
                .appendingPathComponent("LaunchScope", isDirectory: true)
                .appendingPathComponent("scan-snapshot.json")
        }
    }

    func load() throws -> ScanSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.snapshotDecoder.decode(ScanSnapshot.self, from: data)
    }

    func save(_ snapshot: ScanSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.snapshotEncoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var snapshotEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var snapshotDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

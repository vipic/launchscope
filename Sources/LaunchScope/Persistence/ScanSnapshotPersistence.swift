import Foundation

protocol ScanSnapshotPersisting: Sendable {
    func loadHistory() throws -> [ScanSnapshot]
    func saveHistory(_ snapshots: [ScanSnapshot]) throws
}

struct ScanSnapshotArchive: Codable, Equatable, Sendable {
    var schemaVersion = 2
    var snapshots: [ScanSnapshot]
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

    func loadHistory() throws -> [ScanSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder.snapshotDecoder
        if let archive = try? decoder.decode(ScanSnapshotArchive.self, from: data) {
            return archive.snapshots.sorted { $0.scannedAt < $1.scannedAt }
        }
        return [try decoder.decode(ScanSnapshot.self, from: data)]
    }

    func saveHistory(_ snapshots: [ScanSnapshot]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let retained = Array(snapshots.sorted { $0.scannedAt < $1.scannedAt }.suffix(30))
        let data = try JSONEncoder.snapshotEncoder.encode(ScanSnapshotArchive(snapshots: retained))
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

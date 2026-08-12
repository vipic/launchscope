import CryptoKit
import SwiftUI
import XCTest

enum SnapshotTestSupport {
    @MainActor
    static func assertSnapshot<V: View>(named name: String, size: CGSize, view: V) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LAUNCHSCOPE_SNAPSHOT_TESTS"] == "1"
                || environment["LAUNCHSCOPE_RECORD_SNAPSHOTS"] == "1" else {
            throw XCTSkip("设置 LAUNCHSCOPE_SNAPSHOT_TESTS=1 验证快照，或设置 LAUNCHSCOPE_RECORD_SNAPSHOTS=1 录制快照")
        }

        let actual = try renderPNG(view: view, size: size)
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
        let baseline = directory.appendingPathComponent("\(name).png")
        if environment["LAUNCHSCOPE_RECORD_SNAPSHOTS"] == "1" {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try actual.write(to: baseline, options: .atomic)
            return
        }

        let expected = try Data(contentsOf: baseline)
        guard digest(actual) == digest(expected) else {
            let failure = directory.appendingPathComponent("\(name).actual.png")
            try? actual.write(to: failure, options: .atomic)
            XCTFail("快照不匹配：\(name)；实际图像已写入 \(failure.path)")
            return
        }
    }

    @MainActor
    private static func renderPNG<V: View>(view: V, size: CGSize) throws -> Data {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw SnapshotError.renderFailed
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.renderFailed
        }
        return data
    }

    private static func digest(_ data: Data) -> SHA256.Digest { SHA256.hash(data: data) }

    private enum SnapshotError: Error { case renderFailed }
}

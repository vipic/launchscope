import Foundation
import XCTest
@testable import LaunchScope

final class BackgroundTaskCacheTests: XCTestCase {
    func testLegacyCacheReparsesRelativePathsWithoutChangingIdentityOrTimestamp() throws {
        let cache = makeCache()
        let app = cache.url.deletingLastPathComponent().appendingPathComponent("Example.app")
        let target = app.appendingPathComponent("Contents/Helper App.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let parent = StartupItem(id: "btm:PARENT:\(app.path)", label: "parent", source: .backgroundTask,
                                 configuration: ["UUID": "PARENT", "Identifier": "parent", "URL": app.absoluteString])
        let child = StartupItem(id: "btm:CHILD:Contents/Helper%20App.app", label: "child", source: .loginItem,
                                executablePath: "Contents/Helper%20App.app",
                                configuration: ["UUID": "CHILD", "Identifier": "child", "Parent Identifier": "parent",
                                                "URL": "Contents/Helper%20App.app", "Type": "login item"], targetExists: false)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try cache.save(items: [parent, child], updatedAt: date)
        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.updatedAt, date)
        XCTAssertEqual(loaded.items[1].id, child.id)
        XCTAssertEqual(loaded.items[1].executablePath, target.path)
        XCTAssertEqual(loaded.items[1].targetExists, true)
    }

    func testNormalLoadUsesCacheWithoutRunningSFLTool() throws {
        let cache = makeCache()
        let cachedItem = StartupItem(
            id: "btm:cached",
            label: "com.example.cached",
            source: .backgroundTask
        )
        try cache.save(items: [cachedItem])
        let provider = BackgroundTaskProvider(
            scanner: BackgroundTaskScanner(runner: StubCommandRunner(result: CommandResult(
                standardOutput: "",
                standardError: "runner should not be called",
                exitCode: 99,
                timedOut: false
            ))),
            cache: cache
        )

        let result = provider.items(refresh: false)

        XCTAssertEqual(result.items, [cachedItem])
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertNotNil(result.updatedAt)
    }

    func testExplicitRefreshStoresSuccessfulResult() throws {
        let cache = makeCache()
        let provider = BackgroundTaskProvider(
            scanner: BackgroundTaskScanner(runner: StubCommandRunner(result: CommandResult(
                standardOutput: """
                #1:
                UUID: FRESH
                Name: Fresh Helper
                Type: agent (0x8)
                Disposition: [enabled, allowed] (0x3)
                Identifier: com.example.fresh

                """,
                standardError: "",
                exitCode: 0,
                timedOut: false
            ))),
            cache: cache
        )

        let result = provider.items(refresh: true)

        XCTAssertEqual(result.items.first?.label, "com.example.fresh")
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(try cache.load()?.items.first?.label, "com.example.fresh")
    }

    func testFailedRefreshPreservesLastSuccessfulSnapshot() throws {
        let cache = makeCache()
        let cachedItem = StartupItem(
            id: "btm:last-good",
            label: "com.example.last-good",
            source: .backgroundTask
        )
        try cache.save(items: [cachedItem])
        let provider = BackgroundTaskProvider(
            scanner: BackgroundTaskScanner(runner: StubCommandRunner(result: CommandResult(
                standardOutput: "",
                standardError: "authorization failed",
                exitCode: 1,
                timedOut: false
            ))),
            cache: cache
        )

        let result = provider.items(refresh: true)

        XCTAssertEqual(result.items, [cachedItem])
        XCTAssertEqual(result.issues.first?.source, "后台任务管理")
        XCTAssertEqual(try cache.load()?.items, [cachedItem])
    }

    private func makeCache() -> BackgroundTaskCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("launchscope-cache-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return BackgroundTaskCache(url: directory.appendingPathComponent("background-tasks.json"))
    }
}

private struct StubCommandRunner: CommandRunning {
    var result: CommandResult

    func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
        result
    }
}

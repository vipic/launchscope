import XCTest
@testable import LaunchScope

final class StartupItemPresentationTests: XCTestCase {
    func testUnattributedItemsAreNotGroupedTogether() {
        let first = StartupItem(
            id: "launchd:/one.plist",
            label: "com.example.one",
            displayName: "One",
            source: .userLaunchAgent
        )
        let second = StartupItem(
            id: "launchd:/two.plist",
            label: "com.example.two",
            displayName: "Two",
            source: .userLaunchAgent
        )

        XCTAssertEqual(StartupItemListData.groups(for: [first, second]).count, 2)
    }

    func testHomebrewAndLaunchdRecordsShareOneGroup() {
        let service = StartupItem(
            id: "homebrew:ollama",
            label: "homebrew.mxcl.ollama",
            displayName: "ollama",
            source: .homebrewService
        )
        let plist = StartupItem(
            id: "launchd:/ollama.plist",
            label: "homebrew.mxcl.ollama",
            source: .userLaunchAgent
        )

        let group = StartupItemListData.groups(for: [plist, service])
        XCTAssertEqual(group.count, 1)
        XCTAssertEqual(group[0].name, "ollama")
        XCTAssertEqual(group[0].items.first?.source, .homebrewService)
    }

    func testHomebrewExplanationDoesNotClaimExactCreator() {
        let item = StartupItem(
            id: "homebrew:ollama",
            label: "homebrew.mxcl.ollama",
            displayName: "ollama",
            source: .homebrewService,
            keepAliveDescription: "始终"
        )

        XCTAssertEqual(item.explanation.origin, "Homebrew 服务")
        XCTAssertTrue(item.explanation.reason.contains("通常"))
        XCTAssertTrue(item.explanation.trigger.contains("KeepAlive"))
    }
}

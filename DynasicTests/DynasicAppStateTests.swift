import XCTest

@testable import dynasic

@MainActor
final class DynasicAppStateTests: XCTestCase {
    func testInitialStateUsesDynasicDefaults() {
        let state = DynasicAppState()

        XCTAssertFalse(state.isLyricsVisible)
        XCTAssertEqual(state.lyricsOffset, 0)
        XCTAssertEqual(state.trackTitle, "Nothing Playing")
    }

    func testLyricsVisibilityCanBeToggledThroughState() {
        let state = DynasicAppState()

        state.showLyrics()
        XCTAssertTrue(state.isLyricsVisible)

        state.hideLyrics()
        XCTAssertFalse(state.isLyricsVisible)
    }
}

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

    func testSettingsPersistAcrossStateInstances() {
        let defaults = UserDefaults(suiteName: "dynasic-settings-\(UUID().uuidString)")!
        let firstState = DynasicAppState(userDefaults: defaults)

        firstState.lyricsOffset = 1.25
        firstState.lyricsFontSize = 30
        firstState.lyricsOpacity = 0.7
        firstState.lyricsAlignment = .trailing
        firstState.isClickThrough = true
        firstState.isAlwaysOnTop = false
        firstState.showsPreviousLine = false
        firstState.showsNextLine = false

        let secondState = DynasicAppState(userDefaults: defaults)

        XCTAssertEqual(secondState.lyricsOffset, 1.25)
        XCTAssertEqual(secondState.lyricsFontSize, 30)
        XCTAssertEqual(secondState.lyricsOpacity, 0.7)
        XCTAssertEqual(secondState.lyricsAlignment, .trailing)
        XCTAssertTrue(secondState.isClickThrough)
        XCTAssertFalse(secondState.isAlwaysOnTop)
        XCTAssertFalse(secondState.showsPreviousLine)
        XCTAssertFalse(secondState.showsNextLine)
    }

    func testDiagnosticsTextContainsStableSections() {
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-diagnostics-\(UUID().uuidString)")!
        )

        let text = state.diagnosticsText

        XCTAssertTrue(text.contains("Application"))
        XCTAssertTrue(text.contains("Apple Music"))
        XCTAssertTrue(text.contains("Playback"))
        XCTAssertTrue(text.contains("Lyrics"))
        XCTAssertTrue(text.contains("Network"))
        XCTAssertTrue(text.contains("Errors"))
        XCTAssertTrue(text.contains("backend: not connected"))
        XCTAssertTrue(text.contains("provider: LRCLIB"))
    }
}

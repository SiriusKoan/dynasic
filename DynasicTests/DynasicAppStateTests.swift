import XCTest
import LyricsCore

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

    func testMainWindowUsesDynasicTitleAndCanBeShownAgain() throws {
        let state = DynasicAppState()

        state.showMainWindow()
        let controller = try XCTUnwrap(state.mainWindowControllerForTesting)
        let firstWindow = try XCTUnwrap(controller.window)

        XCTAssertEqual(firstWindow.title, "dynasic")
        XCTAssertTrue(firstWindow.styleMask.contains(.titled))
        XCTAssertTrue(controller.isVisible)

        firstWindow.performClose(nil)
        XCTAssertFalse(controller.isVisible)
        state.showMainWindow()

        XCTAssertTrue(firstWindow === controller.window)
        XCTAssertTrue(controller.isVisible)
        controller.hide()
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
        XCTAssertTrue(text.contains("backend: Apple Events"))
        XCTAssertTrue(text.contains("provider: LRCLIB"))
    }

    func testObservationUpdatesCoordinatorWithoutStartingPollingLoop() async {
        let snapshot = PlaybackSnapshot(
            track: nil,
            state: .paused,
            position: 4.5,
            observedAt: ContinuousClock().now
        )
        let backend = StubObservationBackend(snapshot: snapshot)
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-observation-\(UUID().uuidString)")!,
            musicBackend: backend
        )

        await state.observeOnceForTesting()

        XCTAssertFalse(state.isObservationRunning)
        XCTAssertEqual(state.musicBackendStatus, "connected")
        XCTAssertEqual(state.reportedPlaybackState, .paused)
        XCTAssertEqual(state.reportedPlaybackPosition, 4.5)
        XCTAssertEqual(state.viewState, .nothingPlaying)
    }
}

private struct StubObservationBackend: AppleMusicObservationBackend {
    let snapshot: PlaybackSnapshot

    func snapshot() async throws -> PlaybackSnapshot {
        snapshot
    }
}

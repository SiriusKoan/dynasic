import XCTest
import LyricsCore

@testable import dynasic

@MainActor
final class DynasicAppStateTests: XCTestCase {
    func testInitialStateUsesDynasicDefaults() {
        let state = DynasicAppState()

        XCTAssertFalse(state.isLyricsVisible)
        XCTAssertEqual(state.settings.lyricsOffset, 0)
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

        firstState.settings.lyricsOffset = 1.25
        firstState.settings.lyricsFontSize = 30
        firstState.settings.lyricsOpacity = 0.7
        firstState.settings.lyricsAlignment = .trailing
        firstState.settings.isClickThrough = true
        firstState.settings.isAlwaysOnTop = false
        firstState.settings.showsPreviousLine = false
        firstState.settings.showsNextLine = false

        let secondState = DynasicAppState(userDefaults: defaults)

        XCTAssertEqual(secondState.settings.lyricsOffset, 1.25)
        XCTAssertEqual(secondState.settings.lyricsFontSize, 30)
        XCTAssertEqual(secondState.settings.lyricsOpacity, 0.7)
        XCTAssertEqual(secondState.settings.lyricsAlignment, .trailing)
        XCTAssertTrue(secondState.settings.isClickThrough)
        XCTAssertFalse(secondState.settings.isAlwaysOnTop)
        XCTAssertFalse(secondState.settings.showsPreviousLine)
        XCTAssertFalse(secondState.settings.showsNextLine)
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
        XCTAssertTrue(text.contains("provider: Apple Music cache → LRCLIB"))
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

    func testObservationErrorKeepsMusicUnavailableStateDuringDisplayRefresh() async {
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-observation-error-\(UUID().uuidString)")!,
            musicBackend: FailingObservationBackend()
        )

        await state.observeOnceForTesting()
        await state.refreshViewStateForTesting()

        XCTAssertEqual(state.musicBackendStatus, "unavailable")
        XCTAssertEqual(state.viewState, .musicUnavailable)
        XCTAssertNotNil(state.lastObservationError)
    }
}

private struct StubObservationBackend: AppleMusicObservationBackend {
    let snapshot: PlaybackSnapshot

    func snapshot() async throws -> PlaybackSnapshot {
        snapshot
    }
}

private struct FailingObservationBackend: AppleMusicObservationBackend {
    func snapshot() async throws -> PlaybackSnapshot {
        throw ObservationTestError.unavailable
    }
}

private enum ObservationTestError: Error {
    case unavailable
}

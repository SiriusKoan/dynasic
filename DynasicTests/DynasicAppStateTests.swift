import AppKit
import XCTest
import LyricsCore

@testable import dynasic

@MainActor
final class DynasicAppStateTests: XCTestCase {
    func testInitialStateUsesDynasicDefaults() {
        let state = DynasicAppState()

        XCTAssertFalse(state.isLyricsVisible)
        XCTAssertEqual(state.settings.lyricsOffset, 0)
        XCTAssertEqual(state.settings.lyricsPanelLayout, .expanded)
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
        firstState.settings.lyricsPanelLayout = .lyricsOnly
        firstState.settings.isClickThrough = true
        firstState.settings.isAlwaysOnTop = false
        firstState.settings.isStickyToCorner = true
        firstState.settings.showsPreviousLine = false
        firstState.settings.showsNextLine = false

        let secondState = DynasicAppState(userDefaults: defaults)

        XCTAssertEqual(secondState.settings.lyricsOffset, 1.25)
        XCTAssertEqual(secondState.settings.lyricsFontSize, 30)
        XCTAssertEqual(secondState.settings.lyricsOpacity, 0.7)
        XCTAssertEqual(secondState.settings.lyricsAlignment, .trailing)
        XCTAssertEqual(secondState.settings.lyricsPanelLayout, .lyricsOnly)
        XCTAssertTrue(secondState.settings.isClickThrough)
        XCTAssertFalse(secondState.settings.isAlwaysOnTop)
        XCTAssertTrue(secondState.settings.isStickyToCorner)
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

    func testPlaybackControlsForwardCommandsWithoutBlockingState() async {
        let playbackController = RecordingPlaybackController()
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-controls-\(UUID().uuidString)")!,
            playbackController: playbackController
        )

        let previous = state.previousTrack()
        let playPause = state.togglePlayPause()
        let next = state.nextTrack()

        await previous.value
        await playPause.value
        await next.value

        let commands = await playbackController.commands()
        XCTAssertEqual(commands, [.previousTrack, .playPause, .nextTrack])
        XCTAssertNil(state.lastPlaybackControlError)
    }

    func testPlaybackControlErrorIsExposed() async {
        let playbackController = FailingPlaybackController()
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-control-error-\(UUID().uuidString)")!,
            playbackController: playbackController
        )

        await state.nextTrack().value

        XCTAssertEqual(state.lastPlaybackControlError, "Playback control failed")
    }

    func testUnavailableArtworkIsRequestedOnTrackChangesAndRetriedAfterReturning() async {
        let firstTrack = TrackMetadata(
            title: "First Song",
            artist: "Artist",
            persistentID: "track-1"
        )
        let secondTrack = TrackMetadata(
            title: "Second Song",
            artist: "Artist",
            persistentID: "track-2"
        )
        let backend = SequenceObservationBackend(snapshots: [
            PlaybackSnapshot(
                track: firstTrack,
                state: .playing,
                position: 1,
                observedAt: ContinuousClock().now
            ),
            PlaybackSnapshot(
                track: firstTrack,
                state: .playing,
                position: 2,
                observedAt: ContinuousClock().now
            ),
            PlaybackSnapshot(
                track: secondTrack,
                state: .playing,
                position: 1,
                observedAt: ContinuousClock().now
            ),
            PlaybackSnapshot(
                track: firstTrack,
                state: .playing,
                position: 3,
                observedAt: ContinuousClock().now
            )
        ])
        let artworkProvider = RecordingArtworkProvider()
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-artwork-\(UUID().uuidString)")!,
            musicBackend: backend,
            artworkProvider: artworkProvider
        )

        await state.observeOnceForTesting()
        await state.waitForArtworkForTesting()
        await state.observeOnceForTesting()
        await state.waitForArtworkForTesting()
        await state.observeOnceForTesting()
        await state.waitForArtworkForTesting()
        await state.observeOnceForTesting()
        await state.waitForArtworkForTesting()

        let requests = await artworkProvider.requests()
        XCTAssertEqual(requests, [firstTrack, secondTrack, firstTrack])
        XCTAssertNil(state.trackArtwork)
    }

    func testAvailableArtworkIsCachedByTrackIdentity() async throws {
        let firstTrack = TrackMetadata(
            title: "First Song",
            artist: "Artist",
            persistentID: "track-1"
        )
        let secondTrack = TrackMetadata(
            title: "Second Song",
            artist: "Artist",
            persistentID: "track-2"
        )
        let imageData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let backend = SequenceObservationBackend(snapshots: [
            PlaybackSnapshot(track: firstTrack, state: .playing, position: 1, observedAt: ContinuousClock().now),
            PlaybackSnapshot(track: secondTrack, state: .playing, position: 1, observedAt: ContinuousClock().now),
            PlaybackSnapshot(track: firstTrack, state: .playing, position: 2, observedAt: ContinuousClock().now)
        ])
        let artworkProvider = RecordingArtworkProvider(data: imageData)
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-artwork-cache-\(UUID().uuidString)")!,
            musicBackend: backend,
            artworkProvider: artworkProvider
        )

        for _ in 0..<3 {
            await state.observeOnceForTesting()
            await state.waitForArtworkForTesting()
        }

        let requests = await artworkProvider.requests()
        XCTAssertEqual(requests, [firstTrack, secondTrack])
        XCTAssertNotNil(state.trackArtwork)
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

private actor RecordingPlaybackController: PlaybackControlling {
    private var recordedCommands: [PlaybackControlCommand] = []

    func perform(_ command: PlaybackControlCommand) async throws {
        recordedCommands.append(command)
    }

    func commands() -> [PlaybackControlCommand] {
        recordedCommands
    }
}

private actor FailingPlaybackController: PlaybackControlling {
    func perform(_ command: PlaybackControlCommand) async throws {
        throw PlaybackControlError.scriptFailed("Playback control failed")
    }
}

private actor SequenceObservationBackend: AppleMusicObservationBackend {
    private var snapshots: [PlaybackSnapshot]

    init(snapshots: [PlaybackSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() async throws -> PlaybackSnapshot {
        snapshots.removeFirst()
    }
}

private actor RecordingArtworkProvider: AppleMusicArtworkProviding {
    private let data: Data?
    private var recordedTracks: [TrackMetadata] = []

    init(data: Data? = nil) {
        self.data = data
    }

    func artwork(for track: TrackMetadata) async throws -> Data? {
        recordedTracks.append(track)
        return data
    }

    func requests() -> [TrackMetadata] {
        recordedTracks
    }
}

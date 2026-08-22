import AppKit
import CoreAudio
import XCTest
import LyricsCore

@testable import dynasic

@MainActor
final class DynasicAppStateTests: XCTestCase {
    func testInitialStateUsesDynasicDefaults() {
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-defaults-\(UUID().uuidString)")!
        )

        XCTAssertFalse(state.isLyricsVisible)
        XCTAssertEqual(state.settings.lyricsOffset, 0)
        XCTAssertEqual(state.settings.lyricsPanelLayout, .expanded)
        XCTAssertTrue(state.settings.isIconStickyToCorner)
        XCTAssertTrue(state.settings.isAutoRotateEnabled)
        XCTAssertFalse(state.settings.isWaveformEnabled)
        XCTAssertEqual(state.trackTitle, "Nothing Playing")
    }

    func testLyricsVisibilityCanBeToggledThroughState() {
        let state = DynasicAppState()

        state.showLyrics()
        XCTAssertTrue(state.isLyricsVisible)
        XCTAssertTrue(state.panelControllerForTesting?.isVisible == true)

        state.hideLyrics()
        XCTAssertFalse(state.isLyricsVisible)
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
        firstState.settings.isIconStickyToCorner = false
        firstState.settings.isAutoRotateEnabled = false
        firstState.settings.isWaveformEnabled = true

        let secondState = DynasicAppState(userDefaults: defaults)

        XCTAssertEqual(secondState.settings.lyricsOffset, 1.25)
        XCTAssertEqual(secondState.settings.lyricsFontSize, 30)
        XCTAssertEqual(secondState.settings.lyricsOpacity, 0.7)
        XCTAssertEqual(secondState.settings.lyricsAlignment, .trailing)
        XCTAssertEqual(secondState.settings.lyricsPanelLayout, .lyricsOnly)
        XCTAssertTrue(secondState.settings.isClickThrough)
        XCTAssertFalse(secondState.settings.isAlwaysOnTop)
        XCTAssertFalse(secondState.settings.isIconStickyToCorner)
        XCTAssertFalse(secondState.settings.isAutoRotateEnabled)
        XCTAssertTrue(secondState.settings.isWaveformEnabled)
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
        XCTAssertNil(state.estimatedPlaybackPosition)
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

    func testWaveformFailureKeepsEnabledSettingAndUnavailableState() async {
        let defaults = UserDefaults(suiteName: "dynasic-waveform-failure-\(UUID().uuidString)")!
        let source = FailingWaveformSource(error: .permissionDenied)
        let state = DynasicAppState(
            userDefaults: defaults,
            musicBackend: StubObservationBackend(
                snapshot: PlaybackSnapshot(
                    track: nil,
                    state: .playing,
                    position: 0,
                    observedAt: ContinuousClock().now
                )
            ),
            waveformSource: source
        )
        state.showLyrics()
        state.settings.isWaveformEnabled = true

        await state.observeOnceForTesting()
        await state.waitForWaveformLifecycleForTesting()

        XCTAssertTrue(state.settings.isWaveformEnabled)
        XCTAssertEqual(state.waveformState, .unavailable(.permissionDenied))
        state.hideLyrics()
        XCTAssertEqual(state.waveformState, .unavailable(.permissionDenied))
    }

    func testLyricsOnlyLayoutStartsWaveformCapture() async {
        let source = RecordingWaveformSource()
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-lyrics-only-waveform-\(UUID().uuidString)")!,
            musicBackend: StubObservationBackend(
                snapshot: PlaybackSnapshot(
                    track: nil,
                    state: .playing,
                    position: 0,
                    observedAt: ContinuousClock().now
                )
            ),
            waveformSource: source
        )
        state.showLyrics()
        state.settings.lyricsPanelLayout = .lyricsOnly
        state.settings.isWaveformEnabled = true

        await state.observeOnceForTesting()
        await state.waitForWaveformLifecycleForTesting()

        let startCount = await source.startCount()
        XCTAssertEqual(startCount, 1)
        state.hideLyrics()
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

@MainActor
final class WaveformCoordinatorTests: XCTestCase {
    func testHiddenPanelDoesNotStartCapture() async {
        let source = RecordingWaveformSource()
        let coordinator = WaveformCoordinator(source: source)

        coordinator.reconcile(
            enabled: true,
            panelVisible: false,
            collapsed: false,
            playbackState: .playing
        )
        await Task.yield()

        let startCount = await source.startCount()
        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(coordinator.state, .disabled)
    }

    func testExpandedPlayingStartsCapture() async {
        let source = RecordingWaveformSource()
        let coordinator = WaveformCoordinator(source: source)

        start(coordinator)
        await coordinator.waitForLifecycleForTesting()

        let startCount = await source.startCount()
        XCTAssertEqual(startCount, 1)
        guard case let .running(frame) = coordinator.state else {
            return XCTFail("Expected running waveform state")
        }
        XCTAssertEqual(frame.levels.count, 24)
    }

    func testPauseStopsUpdatesAndRetainsLastFrame() async {
        let source = RecordingWaveformSource()
        let coordinator = WaveformCoordinator(
            source: source,
            timeSource: FixedWaveformTimeSource(value: 1)
        )
        start(coordinator)
        await coordinator.waitForLifecycleForTesting()
        var levels = Array(repeating: Float.zero, count: WaveformFrame.levelCount)
        levels[6] = 1
        await source.emit(WaveformBucket(levels: levels))
        await yieldUntil { coordinator.state.frame?.levels[6] != 0 }
        let lastFrame = coordinator.state.frame

        coordinator.reconcile(
            enabled: true,
            panelVisible: true,
            collapsed: false,
            playbackState: .paused
        )
        await coordinator.waitForLifecycleForTesting()

        XCTAssertEqual(coordinator.state, .paused(lastFrame))
        let stopCount = await source.stopCount()
        XCTAssertEqual(stopCount, 1)
    }

    func testDisablingWaveformStopsCapture() async {
        let source = RecordingWaveformSource()
        let coordinator = WaveformCoordinator(source: source)
        start(coordinator)
        await coordinator.waitForLifecycleForTesting()

        coordinator.reconcile(
            enabled: false,
            panelVisible: true,
            collapsed: false,
            playbackState: .playing
        )
        await coordinator.waitForLifecycleForTesting()

        XCTAssertEqual(coordinator.state, .disabled)
        let stopCount = await source.stopCount()
        XCTAssertEqual(stopCount, 1)
    }

    func testFailureBecomesUnavailableAndToggleRetries() async {
        let source = FailingWaveformSource(error: .permissionDenied)
        let coordinator = WaveformCoordinator(source: source)

        start(coordinator)
        await coordinator.waitForLifecycleForTesting()
        XCTAssertEqual(coordinator.state, .unavailable(.permissionDenied))

        coordinator.reconcile(
            enabled: true,
            panelVisible: true,
            collapsed: false,
            playbackState: .paused
        )
        XCTAssertEqual(coordinator.state, .unavailable(.permissionDenied))

        coordinator.reconcile(
            enabled: false,
            panelVisible: true,
            collapsed: false,
            playbackState: .playing
        )
        start(coordinator)
        await coordinator.waitForLifecycleForTesting()

        let startCount = await source.startCount()
        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(coordinator.state, .unavailable(.permissionDenied))
    }

    func testEndedStreamStopsSourceAndBecomesUnavailable() async {
        let source = RecordingWaveformSource()
        let coordinator = WaveformCoordinator(source: source)
        start(coordinator)
        await coordinator.waitForLifecycleForTesting()

        await source.finish()
        await yieldUntil {
            if case .unavailable = coordinator.state { return true }
            return false
        }

        let stopCount = await source.stopCount()
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(
            coordinator.state,
            .unavailable(.captureFailed("Audio stream ended"))
        )
    }

    func testRapidStopAndRestartDoesNotLetOldGenerationStopNewCapture() async {
        let source = RecordingWaveformSource()
        let coordinator = WaveformCoordinator(source: source)
        start(coordinator)
        await coordinator.waitForLifecycleForTesting()

        coordinator.reconcile(
            enabled: true,
            panelVisible: true,
            collapsed: false,
            playbackState: .paused
        )
        start(coordinator)
        await coordinator.waitForLifecycleForTesting()
        await coordinator.waitForLifecycleForTesting()

        let startCount = await source.startCount()
        let stopCount = await source.stopCount()
        XCTAssertEqual(startCount, 2)
        XCTAssertEqual(stopCount, 1)
        guard case .running = coordinator.state else {
            return XCTFail("Expected restarted waveform capture")
        }
    }

    func testShutdownStopsActiveCapture() async {
        let source = RecordingWaveformSource()
        let coordinator = WaveformCoordinator(source: source)
        start(coordinator)
        await coordinator.waitForLifecycleForTesting()

        await coordinator.shutdown()

        let stopCount = await source.stopCount()
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(coordinator.state, .disabled)
    }

    private func start(_ coordinator: WaveformCoordinator) {
        coordinator.reconcile(
            enabled: true,
            panelVisible: true,
            collapsed: false,
            playbackState: .playing
        )
    }

    private func yieldUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<20 where !condition() {
            await Task.yield()
        }
    }
}

final class WaveformAudioBufferTests: XCTestCase {
    func testRingBufferDropsOldestSamplesWhenFull() throws {
        let ring = WaveformSampleRing()
        for value in 0..<32_774 {
            ring.push(Float(value))
        }

        var values: [Float] = []
        while let sample = ring.pop() {
            values.append(sample)
        }

        XCTAssertEqual(values.count, 32_768)
        XCTAssertEqual(values.first, 6)
        XCTAssertEqual(values.last, 32_773)
    }

    func testFloat32InterleavedPCMProducesMonoSamples() throws {
        let ring = WaveformSampleRing()
        let context = try WaveformCaptureContext(
            format: audioFormat(flags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked),
            ring: ring
        )
        var samples: [Float] = [0.5, -0.5]

        samples.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(bytes.count),
                    mData: bytes.baseAddress
                )
            )
            withUnsafePointer(to: &list) { context.consume($0) }
        }

        XCTAssertEqual(ring.pop() ?? -1, 0, accuracy: 0.0001)
    }

    func testInt16NonInterleavedPCMProducesMonoSamples() throws {
        let ring = WaveformSampleRing()
        let context = try WaveformCaptureContext(
            format: audioFormat(
                flags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                bitsPerChannel: 16,
                bytesPerFrame: 2,
                nonInterleaved: true
            ),
            ring: ring
        )
        var left: [Int16] = [16_384]
        var right: [Int16] = [-16_384]
        let byteCount = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
        let rawList = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawList.deallocate() }
        let list = rawList.bindMemory(to: AudioBufferList.self, capacity: 1)

        left.withUnsafeMutableBytes { leftBytes in
            right.withUnsafeMutableBytes { rightBytes in
                list.initialize(to: AudioBufferList(
                    mNumberBuffers: 2,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(leftBytes.count),
                        mData: leftBytes.baseAddress
                    )
                ))
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                buffers[1] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(rightBytes.count),
                    mData: rightBytes.baseAddress
                )
                context.consume(UnsafePointer(list))
                list.deinitialize(count: 1)
            }
        }

        XCTAssertEqual(ring.pop() ?? -1, 0, accuracy: 0.0001)
    }

    func testStoppedCallbackContextDoesNotWriteMoreSamples() throws {
        let ring = WaveformSampleRing()
        let context = try WaveformCaptureContext(
            format: audioFormat(flags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked),
            ring: ring
        )
        context.stopAcceptingCallbacks()
        var samples: [Float] = [1, 1]

        samples.withUnsafeMutableBytes { bytes in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(bytes.count),
                    mData: bytes.baseAddress
                )
            )
            withUnsafePointer(to: &list) { context.consume($0) }
        }
        context.waitForCallbacksToFinish()

        XCTAssertNil(ring.pop())
    }

    func testRejectsPaddedNonInterleavedPCM() {
        let ring = WaveformSampleRing()
        let format = audioFormat(
            flags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            bitsPerChannel: 16,
            bytesPerFrame: 4,
            nonInterleaved: true
        )

        XCTAssertThrowsError(try WaveformCaptureContext(format: format, ring: ring)) { error in
            XCTAssertEqual(error as? AppleMusicWaveformError, .unsupportedFormat)
        }
    }

    func testSpectrumBandIndexUsesTwentyHertzToTwentyKilohertzLogScale() {
        XCTAssertEqual(WaveformSpectrumAnalyzer.bandIndex(for: 20), 0)
        XCTAssertEqual(WaveformSpectrumAnalyzer.bandIndex(for: 100), 5)
        XCTAssertEqual(WaveformSpectrumAnalyzer.bandIndex(for: 1_000), 13)
        XCTAssertEqual(WaveformSpectrumAnalyzer.bandIndex(for: 10_000), 21)
        XCTAssertEqual(WaveformSpectrumAnalyzer.bandIndex(for: 20_000), 23)
        XCTAssertNil(WaveformSpectrumAnalyzer.bandIndex(for: 19))
        XCTAssertNil(WaveformSpectrumAnalyzer.bandIndex(for: 20_001))
    }

    func testSpectrumAnalyzerMapsToneFrequencyToExpectedBin() throws {
        for (frequency, expectedBand) in [(100.0, 5), (1_000.0, 13), (10_000.0, 21)] {
            let bucket = try spectrumBucket(frequency: frequency, amplitude: 1)
            let strongestBand = try XCTUnwrap(
                bucket.levels.enumerated().max(by: { $0.element < $1.element })?.offset
            )
            XCTAssertEqual(strongestBand, expectedBand)
        }
    }

    func testSpectrumAnalyzerPreservesAmplitudeDifferenceInDecibels() throws {
        let loud = try spectrumBucket(frequency: 1_000, amplitude: 1).levels[13]
        let halfAmplitude = try spectrumBucket(frequency: 1_000, amplitude: 0.5).levels[13]

        XCTAssertEqual(loud - halfAmplitude, 6.0206 / 72, accuracy: 0.01)
    }

    func testSpectrumAnalyzerMapsSilenceToZero() throws {
        let bucket = try spectrumBucket(frequency: 1_000, amplitude: 0)

        XCTAssertTrue(bucket.levels.allSatisfy { $0 == 0 })
    }

    private func spectrumBucket(
        frequency: Double,
        amplitude: Float,
        sampleRate: Double = 48_000
    ) throws -> WaveformBucket {
        let analyzer = try XCTUnwrap(WaveformSpectrumAnalyzer(sampleRate: sampleRate))
        for index in 0..<WaveformSpectrumAnalyzer.sampleCount {
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            analyzer.append(amplitude * Float(sin(phase)))
        }
        return try XCTUnwrap(analyzer.makeBucket())
    }

    private func audioFormat(
        flags: AudioFormatFlags,
        bitsPerChannel: UInt32 = 32,
        bytesPerFrame: UInt32 = 8,
        nonInterleaved: Bool = false
    ) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: 20,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags | (nonInterleaved ? kAudioFormatFlagIsNonInterleaved : 0),
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: 2,
            mBitsPerChannel: bitsPerChannel,
            mReserved: 0
        )
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

private actor RecordingWaveformSource: WaveformSource {
    private var starts = 0
    private var stops = 0
    private var continuation: AsyncStream<WaveformBucket>.Continuation?

    func start() async throws -> AsyncStream<WaveformBucket> {
        starts += 1
        let pair = AsyncStream<WaveformBucket>.makeStream(bufferingPolicy: .bufferingNewest(64))
        continuation = pair.continuation
        return pair.stream
    }

    func stop() async {
        stops += 1
        continuation?.finish()
        continuation = nil
    }

    func emit(_ bucket: WaveformBucket) {
        continuation?.yield(bucket)
    }

    func finish() {
        continuation?.finish()
    }

    func startCount() -> Int { starts }
    func stopCount() -> Int { stops }
}

private actor FailingWaveformSource: WaveformSource {
    private let error: AppleMusicWaveformError
    private var starts = 0

    init(error: AppleMusicWaveformError) {
        self.error = error
    }

    func start() async throws -> AsyncStream<WaveformBucket> {
        starts += 1
        throw error
    }

    func stop() async {}

    func startCount() -> Int { starts }
}

private struct FixedWaveformTimeSource: MonotonicTimeSource {
    let value: TimeInterval

    func now() -> TimeInterval { value }
}

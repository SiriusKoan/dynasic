import Foundation
import Testing

@testable import LyricsCore

private actor MockLyricsProvider: LyricsProvider {
    enum ProviderError: Error, Equatable, Sendable {
        case failed
    }

    private var results: [TrackIdentity: Result<Lyrics?, ProviderError>] = [:]
    private var requests: [TrackMetadata] = []
    private var pending: [TrackIdentity: CheckedContinuation<Lyrics?, Error>] = [:]
    private var requestWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func setResult(
        _ result: Result<Lyrics?, ProviderError>,
        for track: TrackMetadata
    ) {
        results[TrackIdentity(metadata: track)] = result
    }

    func lyrics(for track: TrackMetadata) async throws -> Lyrics? {
        let identity = TrackIdentity(metadata: track)
        requests.append(track)
        notifyRequestWaiters()

        if let result = results[identity] {
            return try result.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending[identity] = continuation
        }
    }

    func resolve(_ lyrics: Lyrics?, for track: TrackMetadata) {
        let identity = TrackIdentity(metadata: track)
        pending.removeValue(forKey: identity)?.resume(returning: lyrics)
    }

    func requestCount() -> Int {
        requests.count
    }

    func waitForRequestCount(_ expected: Int) async {
        guard requests.count < expected else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((expected, continuation))
        }
    }

    private func notifyRequestWaiters() {
        let ready = requestWaiters.filter { $0.0 <= requests.count }
        requestWaiters.removeAll { $0.0 <= requests.count }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }
}

private final class CoordinatorFakeClock: MonotonicTimeSource, @unchecked Sendable {
    var currentTime: TimeInterval = 0

    func now() -> TimeInterval { currentTime }

    func advance(by seconds: TimeInterval) {
        currentTime += seconds
    }
}

@Test
func coordinatorFetchesOneTimeForRepeatedSnapshots() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = MockLyricsProvider()
    let track = coordinatorTrack(title: "A")
    let coordinator = LyricsCoordinator(
        provider: provider,
        cache: LyricsCache(directory: directory)
    )

    await coordinator.process(snapshot: coordinatorSnapshot(track: track, position: 10))
    await provider.waitForRequestCount(1)
    for _ in 0..<20 {
        await coordinator.process(snapshot: coordinatorSnapshot(track: track, position: 10))
    }

    #expect(await provider.requestCount() == 1)
    await provider.resolve(nil, for: track)
}

@Test
func coordinatorLoadsCacheWithoutCallingProvider() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = MockLyricsProvider()
    let cache = LyricsCache(directory: directory)
    let track = coordinatorTrack(title: "A")
    let lyrics = coordinatorLyrics(text: "cached")
    #expect(await cache.store(lyrics, for: track))
    let coordinator = LyricsCoordinator(provider: provider, cache: cache)

    await coordinator.process(snapshot: coordinatorSnapshot(track: track, position: 10))

    #expect(await provider.requestCount() == 0)
    #expect(await waitUntil {
        if case let .displaying(_, loadedLyrics, _) = await coordinator.currentState() {
            return loadedLyrics == lyrics
        }
        return false
    })
}

@Test
func coordinatorFetchesNewTrackAfterTrackChange() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = MockLyricsProvider()
    let trackA = coordinatorTrack(title: "A")
    let trackB = coordinatorTrack(title: "B")
    await provider.setResult(.success(coordinatorLyrics(text: "B lyrics")), for: trackB)
    let coordinator = LyricsCoordinator(
        provider: provider,
        cache: LyricsCache(directory: directory)
    )

    await coordinator.process(snapshot: coordinatorSnapshot(track: trackA, position: 10))
    await provider.waitForRequestCount(1)
    await coordinator.process(snapshot: coordinatorSnapshot(track: trackB, position: 10))
    await provider.waitForRequestCount(2)

    #expect(await provider.requestCount() == 2)
    #expect(await waitUntil {
        if case let .displaying(track, _, _) = await coordinator.currentState() {
            return track.title == "B"
        }
        return false
    })
    await provider.resolve(nil, for: trackA)
}

@Test
func lateResponseForOldTrackIsIgnored() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = MockLyricsProvider()
    let trackA = coordinatorTrack(title: "A")
    let trackB = coordinatorTrack(title: "B")
    let lyricsA = coordinatorLyrics(text: "A lyrics")
    let lyricsB = coordinatorLyrics(text: "B lyrics")
    await provider.setResult(.success(lyricsB), for: trackB)
    let coordinator = LyricsCoordinator(
        provider: provider,
        cache: LyricsCache(directory: directory)
    )

    await coordinator.process(snapshot: coordinatorSnapshot(track: trackA, position: 10))
    await provider.waitForRequestCount(1)
    await coordinator.process(snapshot: coordinatorSnapshot(track: trackB, position: 10))
    await provider.waitForRequestCount(2)
    await provider.resolve(lyricsA, for: trackA)

    #expect(await waitUntil {
        if case let .displaying(track, loadedLyrics, _) = await coordinator.currentState() {
            return track.title == "B" && loadedLyrics == lyricsB
        }
        return false
    })
}

@Test
func coordinatorUpdatesPlaybackClockAndSeekSelection() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fakeClock = CoordinatorFakeClock()
    let provider = MockLyricsProvider()
    let track = coordinatorTrack(title: "A")
    let lyrics = Lyrics(lines: [
        LyricLine(timestamp: 10, text: "A"),
        LyricLine(timestamp: 20, text: "B")
    ])
    await provider.setResult(.success(lyrics), for: track)
    let coordinator = LyricsCoordinator(
        provider: provider,
        cache: LyricsCache(directory: directory),
        playbackClock: PlaybackClock(timeSource: fakeClock)
    )

    await coordinator.process(snapshot: coordinatorSnapshot(track: track, position: 10))
    #expect(await waitUntil {
        if case let .displaying(_, _, currentIndex) = await coordinator.currentState() {
            return currentIndex == 0
        }
        return false
    })
    fakeClock.advance(by: 100)
    await coordinator.process(snapshot: coordinatorSnapshot(
        track: track,
        state: .paused,
        position: 10
    ))
    #expect(await coordinator.currentPosition() == 10)

    await coordinator.process(snapshot: coordinatorSnapshot(
        track: track,
        state: .playing,
        position: 20
    ))
    #expect(await waitUntil {
        if case let .displaying(_, _, currentIndex) = await coordinator.currentState() {
            return currentIndex == 1
        }
        return false
    })
    await coordinator.process(snapshot: coordinatorSnapshot(
        track: track,
        state: .playing,
        position: 10
    ))
    #expect(await waitUntil {
        if case let .displaying(_, _, currentIndex) = await coordinator.currentState() {
            return currentIndex == 0
        }
        return false
    })
}

@Test
func coordinatorRefreshesLyricSelectionFromLocalClock() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fakeClock = CoordinatorFakeClock()
    let provider = MockLyricsProvider()
    let track = coordinatorTrack(title: "A")
    let lyrics = Lyrics(lines: [
        LyricLine(timestamp: 10, text: "A"),
        LyricLine(timestamp: 20, text: "B")
    ])
    await provider.setResult(.success(lyrics), for: track)
    let coordinator = LyricsCoordinator(
        provider: provider,
        cache: LyricsCache(directory: directory),
        playbackClock: PlaybackClock(timeSource: fakeClock)
    )

    await coordinator.process(snapshot: coordinatorSnapshot(track: track, position: 10))
    #expect(await waitUntil {
        if case let .displaying(_, _, currentIndex) = await coordinator.currentState() {
            return currentIndex == 0
        }
        return false
    })

    fakeClock.advance(by: 10)

    let display = await coordinator.currentDisplay()
    #expect(display.position == 20)
    if case let .displaying(_, _, currentIndex) = display.state {
        #expect(currentIndex == 1)
    } else {
        Issue.record("Expected displaying state")
    }
}

@Test
func coordinatorReportsNextLyricChangePositionFromLocalClock() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fakeClock = CoordinatorFakeClock()
    let provider = MockLyricsProvider()
    let track = coordinatorTrack(title: "A")
    let lyrics = Lyrics(lines: [
        LyricLine(timestamp: 10, text: "A"),
        LyricLine(timestamp: 20, text: "B"),
        LyricLine(timestamp: 30, text: "C")
    ])
    await provider.setResult(.success(lyrics), for: track)
    let coordinator = LyricsCoordinator(
        provider: provider,
        cache: LyricsCache(directory: directory),
        playbackClock: PlaybackClock(timeSource: fakeClock)
    )

    await coordinator.process(snapshot: coordinatorSnapshot(track: track, position: 10))
    #expect(await waitUntil {
        if case let .displaying(_, _, currentIndex) = await coordinator.currentState() {
            return currentIndex == 0
        }
        return false
    })

    #expect(await coordinator.nextLyricChangePosition() == 20)
    fakeClock.advance(by: 10.1)
    #expect(await coordinator.nextLyricChangePosition() == 30)
}

@Test
func coordinatorReturnsSelectionAndNextBoundaryWithDuplicateTimestampsAndOffset() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let track = coordinatorTrack(title: "Boundary")
    let lyrics = Lyrics(lines: [
        LyricLine(timestamp: 10, text: "First"),
        LyricLine(timestamp: 10, text: "Duplicate"),
        LyricLine(timestamp: 20, text: "Last")
    ], metadata: LyricsMetadata(offsetMilliseconds: 250))
    let cache = LyricsCache(directory: directory)
    _ = await cache.store(lyrics, for: track)
    let coordinator = LyricsCoordinator(provider: MockLyricsProvider(), cache: cache)

    for (position, expectedIndex, next) in [
        (9.0, nil, 10.25), (10.25, 1, 20.25), (20.25, 2, nil)
    ] as [(Double, Int?, Double?)] {
        await coordinator.process(snapshot: coordinatorSnapshot(track: track, state: .paused, position: position))
        let display = await coordinator.currentDisplay()
        #expect(display.position == position)
        #expect(display.nextLyricChangePosition == next)
        #expect(display.state == .displaying(track: track, lyrics: lyrics, currentIndex: expectedIndex))
    }
}

@Test
func coordinatorNotifiesWhenLyricsFinishAndSupportsSubscriptionRestart() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = MockLyricsProvider()
    let track = coordinatorTrack(title: "Loaded")
    let lyrics = coordinatorLyrics(text: "Ready")
    await provider.setResult(.success(lyrics), for: track)
    let coordinator = LyricsCoordinator(provider: provider, cache: LyricsCache(directory: directory))
    var updates = await coordinator.lyricsUpdates().makeAsyncIterator()
    #expect(await updates.next() != nil)

    await coordinator.process(snapshot: coordinatorSnapshot(track: track, state: .paused, position: 10))
    #expect(await updates.next() != nil)
    #expect(await coordinator.currentState() == .displaying(track: track, lyrics: lyrics, currentIndex: 0))

    var restarted = await coordinator.lyricsUpdates().makeAsyncIterator()
    #expect(await updates.next() == nil)
    #expect(await restarted.next() != nil)
}

@Test
func providerFailureIsRecoverableOnNextTrack() async throws {
    let directory = try makeCoordinatorDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = MockLyricsProvider()
    let trackA = coordinatorTrack(title: "A")
    let trackB = coordinatorTrack(title: "B")
    await provider.setResult(.failure(.failed), for: trackA)
    await provider.setResult(.success(coordinatorLyrics(text: "B lyrics")), for: trackB)
    let coordinator = LyricsCoordinator(
        provider: provider,
        cache: LyricsCache(directory: directory)
    )

    await coordinator.process(snapshot: coordinatorSnapshot(track: trackA, position: 10))
    #expect(await waitUntil {
        await coordinator.currentState() == .error(.providerFailed)
    })
    await coordinator.process(snapshot: coordinatorSnapshot(track: trackB, position: 10))

    #expect(await waitUntil {
        if case let .displaying(track, _, _) = await coordinator.currentState() {
            return track.title == "B"
        }
        return false
    })
}

private func coordinatorTrack(title: String) -> TrackMetadata {
    TrackMetadata(
        title: title,
        artist: "Artist",
        album: "Album",
        duration: 100,
        persistentID: title
    )
}

private func coordinatorLyrics(text: String) -> Lyrics {
    Lyrics(lines: [LyricLine(timestamp: 10, text: text)])
}

private func coordinatorSnapshot(
    track: TrackMetadata?,
    state: PlaybackState = .playing,
    position: TimeInterval?
) -> PlaybackSnapshot {
    PlaybackSnapshot(
        track: track,
        state: state,
        position: position,
        observedAt: ContinuousClock().now
    )
}

private func makeCoordinatorDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("dynasic-coordinator-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

private func waitUntil(
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<100 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

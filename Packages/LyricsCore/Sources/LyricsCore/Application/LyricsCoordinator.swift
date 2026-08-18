import Foundation

public enum LyricsCoordinatorError: Error, Equatable, Sendable {
    case providerFailed
}

public enum LyricsViewState: Sendable, Equatable {
    case idle
    case musicUnavailable
    case nothingPlaying
    case loading(TrackMetadata)
    case displaying(track: TrackMetadata, lyrics: Lyrics, currentIndex: Int?)
    case noLyrics(TrackMetadata)
    case error(LyricsCoordinatorError)
}

public actor LyricsCoordinator {
    private let provider: any LyricsProvider
    private let cache: LyricsCache
    private var playbackClock: PlaybackClock
    private var activeTrackIdentity: TrackIdentity?
    private var activeTrack: TrackMetadata?
    private var lyricsTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    public private(set) var state: LyricsViewState = .idle

    public init(
        provider: any LyricsProvider,
        cache: LyricsCache,
        playbackClock: PlaybackClock = PlaybackClock()
    ) {
        self.provider = provider
        self.cache = cache
        self.playbackClock = playbackClock
    }

    public func process(snapshot: PlaybackSnapshot) async {
        playbackClock.synchronize(
            position: snapshot.position,
            state: snapshot.state,
            observationLatency: snapshot.observationLatency
        )

        guard let track = snapshot.track else {
            clearActiveTrack()
            state = .nothingPlaying
            return
        }

        let identity = TrackIdentity(metadata: track)
        if identity != activeTrackIdentity {
            await startTrack(track, identity: identity)
        } else {
            activeTrack = track
            refreshDisplayedState()
        }
    }

    public func currentState() -> LyricsViewState {
        refreshDisplayedState()
        return state
    }

    public func currentPosition() -> TimeInterval? {
        playbackClock.currentPosition()
    }

    public func cancel() {
        clearActiveTrack()
        state = .idle
    }

    private func startTrack(_ track: TrackMetadata, identity: TrackIdentity) async {
        lyricsTask?.cancel()
        lyricsTask = nil
        generation &+= 1
        let requestGeneration = generation
        activeTrackIdentity = identity
        activeTrack = track
        state = .loading(track)

        if let cachedLyrics = await cache.load(for: track) {
            guard isCurrent(identity: identity, generation: requestGeneration) else { return }
            state = displayingState(track: track, lyrics: cachedLyrics)
            return
        }

        let provider = self.provider
        let cache = self.cache
        lyricsTask = Task { [weak self] in
            do {
                let lyrics = try await provider.lyrics(for: track)
                guard let self else { return }
                await self.finish(
                    track: track,
                    identity: identity,
                    generation: requestGeneration,
                    lyrics: lyrics,
                    cache: cache
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                await self.fail(
                    identity: identity,
                    generation: requestGeneration
                )
            }
        }
    }

    private func finish(
        track: TrackMetadata,
        identity: TrackIdentity,
        generation: UInt64,
        lyrics: Lyrics?,
        cache: LyricsCache
    ) async {
        guard isCurrent(identity: identity, generation: generation) else { return }
        lyricsTask = nil

        guard let lyrics else {
            state = .noLyrics(track)
            return
        }

        state = displayingState(track: track, lyrics: lyrics)
        _ = await cache.store(lyrics, for: track)
    }

    private func fail(identity: TrackIdentity, generation: UInt64) {
        guard isCurrent(identity: identity, generation: generation) else { return }
        lyricsTask = nil
        state = .error(.providerFailed)
    }

    private func refreshDisplayedState() {
        guard case let .displaying(_, lyrics, _) = state,
              let activeTrack else {
            return
        }
        state = displayingState(track: activeTrack, lyrics: lyrics)
    }

    private func displayingState(track: TrackMetadata, lyrics: Lyrics) -> LyricsViewState {
        let currentIndex = playbackClock.currentPosition().map {
            LyricSelector.select(lyrics: lyrics, position: $0).currentIndex
        } ?? nil
        return .displaying(
            track: track,
            lyrics: lyrics,
            currentIndex: currentIndex
        )
    }

    private func isCurrent(identity: TrackIdentity, generation: UInt64) -> Bool {
        activeTrackIdentity == identity && self.generation == generation
    }

    private func clearActiveTrack() {
        lyricsTask?.cancel()
        lyricsTask = nil
        generation &+= 1
        activeTrackIdentity = nil
        activeTrack = nil
    }
}

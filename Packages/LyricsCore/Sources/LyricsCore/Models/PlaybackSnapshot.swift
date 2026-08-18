import Foundation

public struct PlaybackSnapshot: Sendable, Equatable {
    public let track: TrackMetadata?
    public let state: PlaybackState
    public let position: TimeInterval?
    public let observedAt: ContinuousClock.Instant

    public init(
        track: TrackMetadata?,
        state: PlaybackState,
        position: TimeInterval?,
        observedAt: ContinuousClock.Instant
    ) {
        self.track = track
        self.state = state
        self.position = position
        self.observedAt = observedAt
    }
}

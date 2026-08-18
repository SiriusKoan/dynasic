import Foundation

public protocol MonotonicTimeSource: Sendable {
    func now() -> TimeInterval
}

public struct ContinuousClockTimeSource: MonotonicTimeSource, Sendable {
    private let clock: ContinuousClock
    private let origin: ContinuousClock.Instant

    public init(clock: ContinuousClock = ContinuousClock()) {
        self.clock = clock
        self.origin = clock.now
    }

    public func now() -> TimeInterval {
        let duration = origin.duration(to: clock.now)
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

public struct PlaybackClock: Sendable {
    private let timeSource: any MonotonicTimeSource
    private var reportedPosition: TimeInterval?
    private var observedMonotonicTime: TimeInterval?
    private var playbackState: PlaybackState

    public init(
        timeSource: any MonotonicTimeSource = ContinuousClockTimeSource()
    ) {
        self.timeSource = timeSource
        self.reportedPosition = nil
        self.observedMonotonicTime = nil
        self.playbackState = .stopped
    }

    public mutating func synchronize(
        position: TimeInterval?,
        state: PlaybackState
    ) {
        if let position, position.isFinite, position >= 0 {
            reportedPosition = position
            observedMonotonicTime = timeSource.now()
        }
        playbackState = state
    }

    public func currentPosition() -> TimeInterval? {
        guard let reportedPosition else { return nil }
        guard playbackState == .playing,
              let observedMonotonicTime else {
            return reportedPosition
        }

        let elapsed = max(0, timeSource.now() - observedMonotonicTime)
        return reportedPosition + elapsed
    }
}

import Foundation
import Testing

@testable import LyricsCore

private final class FakeClock: MonotonicTimeSource, @unchecked Sendable {
    var currentTime: TimeInterval = 0

    func now() -> TimeInterval {
        currentTime
    }

    func advance(by seconds: TimeInterval) {
        currentTime += seconds
    }
}

@Test
func playingPositionAdvancesFromMonotonicElapsedTime() {
    let fakeClock = FakeClock()
    var playbackClock = PlaybackClock(timeSource: fakeClock)

    playbackClock.synchronize(position: 10, state: .playing)
    fakeClock.advance(by: 0.5)

    #expect(abs((playbackClock.currentPosition() ?? 0) - 10.5) < 0.0001)
}

@Test
func pausedPositionDoesNotAdvance() {
    let fakeClock = FakeClock()
    var playbackClock = PlaybackClock(timeSource: fakeClock)

    playbackClock.synchronize(position: 10, state: .paused)
    fakeClock.advance(by: 100)

    #expect(playbackClock.currentPosition() == 10)
}

@Test
func newSnapshotImmediatelyResynchronizesAfterSeek() {
    let fakeClock = FakeClock()
    var playbackClock = PlaybackClock(timeSource: fakeClock)

    playbackClock.synchronize(position: 100, state: .playing)
    fakeClock.advance(by: 2)
    playbackClock.synchronize(position: 20, state: .playing)

    #expect(playbackClock.currentPosition() == 20)
}

@Test
func newSnapshotCorrectsSmallDrift() {
    let fakeClock = FakeClock()
    var playbackClock = PlaybackClock(timeSource: fakeClock)

    playbackClock.synchronize(position: 100, state: .playing)
    fakeClock.advance(by: 0.91)
    playbackClock.synchronize(position: 101.02, state: .playing)
    fakeClock.advance(by: 0.1)

    #expect(abs((playbackClock.currentPosition() ?? 0) - 101.12) < 0.0001)
}

@Test
func missingPositionRemainsUnavailable() {
    let fakeClock = FakeClock()
    var playbackClock = PlaybackClock(timeSource: fakeClock)

    playbackClock.synchronize(position: nil, state: .playing)

    #expect(playbackClock.currentPosition() == nil)
}

import Testing

@testable import LyricsCore

@Test
func packageLoads() {
    #expect(LyricsCore.packageVersion == "0.1.0")
}

@Test
func playbackPositionDoesNotChangeTrackIdentity() {
    let track = TrackMetadata(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 201.2,
        persistentID: "p.123"
    )
    let clock = ContinuousClock()
    let first = PlaybackSnapshot(
        track: track,
        state: .playing,
        position: 10,
        observedAt: clock.now
    )
    let second = PlaybackSnapshot(
        track: track,
        state: .playing,
        position: 100,
        observedAt: clock.now
    )

    #expect(TrackIdentity(metadata: first.track!) == TrackIdentity(metadata: second.track!))
}

@Test
func persistentIDTakesPriorityOverMetadata() {
    let first = TrackMetadata(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 201.2,
        persistentID: "p.123"
    )
    let second = TrackMetadata(
        title: "Different title",
        artist: "Different artist",
        album: "Different album",
        duration: 999,
        persistentID: "p.123"
    )

    #expect(TrackIdentity(metadata: first) == TrackIdentity(metadata: second))
}

@Test
func fallbackIdentityPreservesVersionMarkers() {
    let regular = TrackMetadata(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 201.2
    )
    let live = TrackMetadata(
        title: "Song (Live)",
        artist: "Artist",
        album: "Album",
        duration: 201.8
    )
    let roundedDuration = TrackMetadata(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 201.8
    )

    #expect(TrackIdentity(metadata: regular) != TrackIdentity(metadata: live))
    #expect(TrackIdentity(metadata: regular) == TrackIdentity(metadata: roundedDuration))
}

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

@Test
func parserSupportsTimestampFormats() {
    let lyrics = LRCParser().parse("""
    [00:01]one
    [00:01.20]two
    [00:01.200]three
    [01:21.52]four
    """)

    #expect(lyrics.lines.map(\.text) == ["one", "two", "three", "four"])
    #expect(abs(lyrics.lines[0].timestamp - 1) < 0.0001)
    #expect(abs(lyrics.lines[1].timestamp - 1.2) < 0.0001)
    #expect(abs(lyrics.lines[2].timestamp - 1.2) < 0.0001)
    #expect(abs(lyrics.lines[3].timestamp - 81.52) < 0.0001)
}

@Test
func parserPreservesUnicodeAndBlankText() {
    let lyrics = LRCParser().parse("""
    [00:01]你好，世界
    [00:02]こんにちは
    [00:03]
    """)

    #expect(lyrics.lines.map(\.text) == ["你好，世界", "こんにちは", ""])
}

@Test
func parserSortsOutOfOrderLinesAndPreservesDuplicateOrder() {
    let lyrics = LRCParser().parse("""
    [00:03]third
    [00:01]first
    [00:02]second-a
    [00:02]second-b
    """)

    #expect(lyrics.lines.map(\.text) == ["first", "second-a", "second-b", "third"])
}

@Test
func parserExtractsMetadataWithoutCreatingLyricLines() {
    let lyrics = LRCParser().parse("""
    [ar: Artist]
    [al: Album]
    [ti: Song]
    [offset:100]
    [00:01]line
    """)

    #expect(lyrics.metadata.artist == "Artist")
    #expect(lyrics.metadata.album == "Album")
    #expect(lyrics.metadata.title == "Song")
    #expect(lyrics.metadata.offsetMilliseconds == 100)
    #expect(lyrics.lines.count == 1)
    #expect(lyrics.lines[0].text == "line")
}

@Test
func parserIgnoresMalformedInputAndEmptyLyrics() {
    let malformed = LRCParser().parse("""
    no timestamp
    [broken
    [00:xx]bad
    [99:60]bad
    """)
    let empty = LRCParser().parse("")

    #expect(malformed.lines.isEmpty)
    #expect(empty.lines.isEmpty)
    #expect(empty.metadata == LyricsMetadata())
}

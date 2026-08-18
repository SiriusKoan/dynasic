import Foundation
import Testing

@testable import LyricsCore

@Test
func cacheRoundTripsLyrics() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let cache = LyricsCache(directory: directory)
    let track = TrackMetadata(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 201.2,
        persistentID: "p.123"
    )
    let lyrics = Lyrics(lines: [LyricLine(timestamp: 1.2, text: "Hello")])

    #expect(await cache.store(lyrics, for: track, providerID: 123))
    #expect(await cache.load(for: track) == lyrics)
}

@Test
func cacheKeyNormalizesTextAndRoundsDuration() {
    let first = TrackMetadata(
        title: " Song ",
        artist: "ARTIST",
        album: "Album",
        duration: 201.2
    )
    let equivalent = TrackMetadata(
        title: "song",
        artist: " artist ",
        album: "album",
        duration: 201.4
    )
    let differentDuration = TrackMetadata(
        title: "song",
        artist: "artist",
        album: "album",
        duration: 201.6
    )

    #expect(LyricsCache.cacheKey(for: first) == LyricsCache.cacheKey(for: equivalent))
    #expect(LyricsCache.cacheKey(for: first) != LyricsCache.cacheKey(for: differentDuration))
}

@Test
func corruptCacheFileIsIgnoredAndRemoved() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let cache = LyricsCache(directory: directory)
    let track = TrackMetadata(title: "Song", artist: "Artist")
    #expect(await cache.store(Lyrics(lines: [LyricLine(timestamp: 1, text: "line")]), for: track))
    let url = await cache.cacheFileURL(for: track)
    try Data("not-json".utf8).write(to: url)

    #expect(await cache.load(for: track) == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test
func oldSchemaIsIgnoredAndRemoved() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let cache = LyricsCache(directory: directory)
    let track = TrackMetadata(title: "Song", artist: "Artist")
    #expect(await cache.store(Lyrics(lines: [LyricLine(timestamp: 1, text: "line")]), for: track))
    let url = await cache.cacheFileURL(for: track)
    try Data("{\"version\":2}".utf8).write(to: url)

    #expect(await cache.load(for: track) == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test
func failedCacheWriteDoesNotThrow() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("dynasic-cache-blocked-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("directory target is a file".utf8).write(to: root)

    let cache = LyricsCache(directory: root)
    let didStore = await cache.store(
        Lyrics(lines: [LyricLine(timestamp: 1, text: "line")]),
        for: TrackMetadata(title: "Song", artist: "Artist")
    )

    #expect(!didStore)
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("dynasic-cache-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

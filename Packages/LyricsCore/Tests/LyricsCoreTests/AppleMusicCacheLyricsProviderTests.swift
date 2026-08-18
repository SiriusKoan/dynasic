import Foundation
import Testing

@testable import LyricsCore

@Test
func appleMusicCacheProviderReadsTimedTTML() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("dynasic-apple-music-cache-\(UUID().uuidString)")
    let cacheDirectory = root.appendingPathComponent("fsCachedData", isDirectory: true)
    try FileManager.default.createDirectory(
        at: cacheDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let response = """
    {
      "data": [{
        "attributes": {
          "name": "Test Song",
          "artistName": "Test Artist",
          "albumName": "Test Album",
          "durationInMillis": 10000
        },
        "relationships": {
          "syllable-lyrics": {
            "data": [{
              "attributes": {
                "ttmlLocalizations": "<tt xmlns=\\\"http://www.w3.org/ns/ttml\\\"><body><p begin=\\\"1.20\\\" end=\\\"2.00\\\">First line</p><p begin=\\\"2.50\\\">Second line</p></body></tt>"
              }
            }]
          }
        }
      }]
    }
    """
    try Data(response.utf8).write(
        to: cacheDirectory.appendingPathComponent("test-response")
    )

    let provider = AppleMusicCacheLyricsProvider(cacheRoot: root)
    let lyrics = try await provider.lyrics(for: TrackMetadata(
        title: "Test Song",
        artist: "Test Artist",
        album: "Test Album",
        duration: 10
    ))

    #expect(lyrics?.lines == [
        LyricLine(timestamp: 1.2, text: "First line"),
        LyricLine(timestamp: 2.5, text: "Second line")
    ])
}

@Test
func appleMusicCacheProviderRejectsWrongTrack() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("dynasic-apple-music-cache-\(UUID().uuidString)")
    let cacheDirectory = root.appendingPathComponent("fsCachedData", isDirectory: true)
    try FileManager.default.createDirectory(
        at: cacheDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let response = """
    {
      "data": [{
        "attributes": {
          "name": "Other Song",
          "artistName": "Other Artist",
          "albumName": "Other Album",
          "durationInMillis": 10000
        },
        "relationships": {
          "syllable-lyrics": {
            "data": [{
              "attributes": {
                "ttmlLocalizations": "<tt xmlns=\\\"http://www.w3.org/ns/ttml\\\"><body><p begin=\\\"1s\\\">Other line</p></body></tt>"
              }
            }]
          }
        }
      }]
    }
    """
    try Data(response.utf8).write(
        to: cacheDirectory.appendingPathComponent("test-response")
    )

    let provider = AppleMusicCacheLyricsProvider(cacheRoot: root)
    let lyrics = try await provider.lyrics(for: TrackMetadata(
        title: "Test Song",
        artist: "Test Artist",
        album: "Test Album",
        duration: 10
    ))

    #expect(lyrics == nil)
}

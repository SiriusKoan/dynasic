import Foundation
import Testing

@testable import LyricsCore

private final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    struct StubResponse {
        let data: Data
        let response: HTTPURLResponse
    }

    private var responses: [StubResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [StubResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            preconditionFailure("MockHTTPClient 沒有下一個 response")
        }
        let response = responses.removeFirst()
        return (response.data, response.response)
    }
}

@Test
func lrclibExactRequestContainsSignatureAndUserAgent() async throws {
    let client = MockHTTPClient(responses: [
        .init(data: Data("{}".utf8), response: httpResponse(statusCode: 404)),
        .init(data: Data("[]".utf8), response: httpResponse(statusCode: 200))
    ])
    let provider = LRCLIBProvider(
        httpClient: client,
        baseURL: URL(string: "https://example.com")!,
        userAgent: "dynasic-test/1.0"
    )
    let track = TrackMetadata(
        title: "Song & Story",
        artist: "Artist",
        album: "Album / Live",
        duration: 201.2
    )

    let result = try await provider.lyrics(for: track)

    #expect(result == nil)
    #expect(client.requests.count == 2)
    #expect(client.requests[0].url?.path == "/api/get")
    #expect(queryValue("track_name", in: client.requests[0]) == "Song & Story")
    #expect(queryValue("artist_name", in: client.requests[0]) == "Artist")
    #expect(queryValue("album_name", in: client.requests[0]) == "Album / Live")
    #expect(queryValue("duration", in: client.requests[0]) == "201.2")
    #expect(client.requests[0].value(forHTTPHeaderField: "User-Agent") == "dynasic-test/1.0")
    #expect(client.requests[1].url?.path == "/api/search")
    #expect(queryValue("q", in: client.requests[1]) == "Song & Story Artist")
    #expect(queryValue("track_name", in: client.requests[1]) == nil)
    #expect(queryValue("artist_name", in: client.requests[1]) == nil)
    #expect(queryValue("album_name", in: client.requests[1]) == nil)
}

@Test
func lrclibDecodesSyncedLyricsFromExactResponse() async throws {
    let json = """
    {
      "id": 1,
      "trackName": "Song",
      "artistName": "Artist",
      "albumName": "Album",
      "duration": 201.2,
      "instrumental": false,
      "plainLyrics": "Hello",
      "syncedLyrics": "[00:01.20]Hello"
    }
    """
    let client = MockHTTPClient(responses: [
        .init(data: Data(json.utf8), response: httpResponse(statusCode: 200))
    ])
    let provider = LRCLIBProvider(
        httpClient: client,
        baseURL: URL(string: "https://example.com")!
    )

    let lyrics = try await provider.lyrics(for: TrackMetadata(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 201.2
    ))

    #expect(lyrics?.lines == [LyricLine(timestamp: 1.2, text: "Hello")])
}

@Test
func lrclibSearchFallbackChoosesBestMatchingSyncedRecord() async throws {
    let searchJSON = """
    [
      {
        "id": 1,
        "trackName": "Song",
        "artistName": "Artist",
        "albumName": "Other Album",
        "duration": 202.0,
        "instrumental": false,
        "plainLyrics": "wrong",
        "syncedLyrics": "[00:01]wrong"
      },
      {
        "id": 2,
        "trackName": " song ",
        "artistName": "ARTIST",
        "albumName": "Album",
        "duration": 201.2,
        "instrumental": false,
        "plainLyrics": "best",
        "syncedLyrics": "[00:01]best"
      }
    ]
    """
    let client = MockHTTPClient(responses: [
        .init(data: Data("{}".utf8), response: httpResponse(statusCode: 404)),
        .init(data: Data(searchJSON.utf8), response: httpResponse(statusCode: 200))
    ])
    let provider = LRCLIBProvider(
        httpClient: client,
        baseURL: URL(string: "https://example.com")!
    )

    let lyrics = try await provider.lyrics(for: TrackMetadata(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 201.2
    ))

    #expect(lyrics?.lines.map(\.text) == ["best"])
}

@Test
func lrclibSearchFallbackFindsFuyubiyoriWhenAlbumMetadataDiffers() async throws {
    let searchJSON = """
    [
      {
        "id": 12253623,
        "trackName": "Fuyubiyori",
        "artistName": "Eri Sasaki",
        "albumName": "Fuyubiyori",
        "duration": 277.0,
        "instrumental": false,
        "plainLyrics": "冬が来るたび思い出す",
        "syncedLyrics": "[00:01.00]冬が来るたび思い出す"
      }
    ]
    """
    let client = MockHTTPClient(responses: [
        .init(data: Data("{}".utf8), response: httpResponse(statusCode: 404)),
        .init(data: Data(searchJSON.utf8), response: httpResponse(statusCode: 200))
    ])
    let provider = LRCLIBProvider(
        httpClient: client,
        baseURL: URL(string: "https://example.com")!
    )

    let lyrics = try await provider.lyrics(for: TrackMetadata(
        title: "Fuyubiyori",
        artist: "Eri Sasaki",
        album: "Fuyubiyori (TV Anime Ending Theme) - EP",
        duration: 277
    ))

    #expect(lyrics?.lines.map(\.text) == ["冬が来るたび思い出す"])
    #expect(queryValue("q", in: client.requests[1]) == "Fuyubiyori Eri Sasaki")
}

@Test
func lrclibSearchFallbackFindsBloomingWithYouWhenResultUsesJapaneseTitle() async throws {
    let searchJSON = """
    [
      {
        "id": 33851710,
        "trackName": "芽吹くとき - Blooming With you",
        "artistName": "yonige",
        "albumName": "Blooming With you",
        "duration": 219.0,
        "instrumental": false,
        "plainLyrics": "芽吹くとき",
        "syncedLyrics": "[00:01.00]芽吹くとき"
      }
    ]
    """
    let client = MockHTTPClient(responses: [
        .init(data: Data("{}".utf8), response: httpResponse(statusCode: 404)),
        .init(data: Data(searchJSON.utf8), response: httpResponse(statusCode: 200))
    ])
    let provider = LRCLIBProvider(
        httpClient: client,
        baseURL: URL(string: "https://example.com")!
    )

    let lyrics = try await provider.lyrics(for: TrackMetadata(
        title: "Blooming With you",
        artist: "yonige",
        album: "Blooming With you - Single",
        duration: 219.2
    ))

    #expect(lyrics?.lines.map(\.text) == ["芽吹くとき"])
}

@Test
func lrclibPlainOnlyResponseFallsBackToSearch() async throws {
    let plainOnly = """
    {
      "id": 1,
      "trackName": "Song",
      "artistName": "Artist",
      "albumName": "Album",
      "duration": 201.2,
      "instrumental": false,
      "plainLyrics": "plain",
      "syncedLyrics": null
    }
    """
    let client = MockHTTPClient(responses: [
        .init(data: Data(plainOnly.utf8), response: httpResponse(statusCode: 200)),
        .init(data: Data("[]".utf8), response: httpResponse(statusCode: 200))
    ])
    let provider = LRCLIBProvider(
        httpClient: client,
        baseURL: URL(string: "https://example.com")!
    )

    #expect(try await provider.lyrics(for: TrackMetadata(
        title: "Song",
        artist: "Artist",
        album: "Album",
        duration: 201.2
    )) == nil)
    #expect(client.requests.count == 2)
}

@Test
func lrclibPropagatesServerErrors() async throws {
    let client = MockHTTPClient(responses: [
        .init(data: Data("{}".utf8), response: httpResponse(statusCode: 500))
    ])
    let provider = LRCLIBProvider(
        httpClient: client,
        baseURL: URL(string: "https://example.com")!
    )

    do {
        _ = try await provider.lyrics(for: TrackMetadata(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 201.2
        ))
        Issue.record("預期 provider 回傳 HTTP 500")
    } catch let error as LRCLIBError {
        #expect(error == .httpStatus(500))
    }
}

@Test
func lrclibRejectsInvalidJSON() async throws {
    let client = MockHTTPClient(responses: [
        .init(data: Data("not-json".utf8), response: httpResponse(statusCode: 200))
    ])
    let provider = LRCLIBProvider(
        httpClient: client,
        baseURL: URL(string: "https://example.com")!
    )

    do {
        _ = try await provider.lyrics(for: TrackMetadata(
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 201.2
        ))
        Issue.record("預期 provider 回傳 invalidPayload")
    } catch let error as LRCLIBError {
        #expect(error == .invalidPayload)
    }
}

@Test
func matcherNormalizesWhitespaceAndCaseWithoutRemovingVersionMarkers() {
    let track = TrackMetadata(title: "Song (Live)", artist: "The Artist", album: "Album", duration: 201.2)
    let candidate = TrackMetadata(title: " song   (LIVE) ", artist: "THE ARTIST", album: "Album", duration: 201.8)
    let regular = TrackMetadata(title: "Song", artist: "The Artist", album: "Album", duration: 201.8)

    #expect(LyricsMatcher.score(track: track, candidate: candidate) == 260)
    #expect(LyricsMatcher.score(track: track, candidate: regular) == nil)
}

@Test
func matcherAcceptsTranslatedTitleAfterDash() {
    let track = TrackMetadata(title: "Blooming With you", artist: "yonige", duration: 219.2)
    let candidate = TrackMetadata(
        title: "芽吹くとき - Blooming With you",
        artist: "yonige",
        duration: 219
    )

    #expect(LyricsMatcher.score(track: track, candidate: candidate) == 240)
}

@Test
func matcherRejectsLargeDurationDrift() {
    let track = TrackMetadata(title: "Song", artist: "Artist", duration: 201)
    let candidate = TrackMetadata(title: "Song", artist: "Artist", duration: 212)

    #expect(LyricsMatcher.score(track: track, candidate: candidate) == nil)
}

private func httpResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func queryValue(_ name: String, in request: URLRequest) -> String? {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return nil
    }
    return components.queryItems?.first(where: { $0.name == name })?.value
}

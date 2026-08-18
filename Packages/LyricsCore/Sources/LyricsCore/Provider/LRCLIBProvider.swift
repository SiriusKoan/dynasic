import Foundation

public enum LRCLIBError: Error, Equatable, Sendable {
    case invalidURL
    case httpStatus(Int)
    case invalidPayload
}

public struct LRCLIBProvider: LyricsProvider, Sendable {
    private let httpClient: any HTTPClient
    private let baseURL: URL
    private let userAgent: String
    private let decoder: JSONDecoder

    public init(
        httpClient: any HTTPClient,
        baseURL: URL = URL(string: "https://lrclib.net")!,
        userAgent: String = "dynasic/0.1.0 (https://github.com/siriuskoan/dynasic)"
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.decoder = JSONDecoder()
    }

    public func lyrics(for track: TrackMetadata) async throws -> Lyrics? {
        if let exactRecord = try await fetchExact(track: track),
           let lyrics = lyrics(from: exactRecord) {
            return lyrics
        }

        guard !normalized(track.title).isEmpty else { return nil }
        let records = try await fetchSearch(track: track)
        guard let bestRecord = bestRecord(for: track, records: records) else {
            return nil
        }
        return lyrics(from: bestRecord)
    }

    private func fetchExact(track: TrackMetadata) async throws -> LRCLIBRecord? {
        guard let album = nonEmpty(track.album),
              let duration = track.duration,
              duration.isFinite,
              duration >= 0,
              !normalized(track.title).isEmpty,
              !normalized(track.artist).isEmpty else {
            return nil
        }

        let request = try makeRequest(
            path: "api/get",
            queryItems: [
                URLQueryItem(name: "track_name", value: track.title),
                URLQueryItem(name: "artist_name", value: track.artist),
                URLQueryItem(name: "album_name", value: album),
                URLQueryItem(name: "duration", value: String(duration))
            ]
        )
        let (data, response) = try await httpClient.data(for: request)
        if response.statusCode == 404 { return nil }
        try validate(response)
        return try decode(LRCLIBRecord.self, from: data)
    }

    private func fetchSearch(track: TrackMetadata) async throws -> [LRCLIBRecord] {
        let searchQuery = [track.title, track.artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let request = try makeRequest(
            path: "api/search",
            queryItems: [URLQueryItem(name: "q", value: searchQuery)]
        )
        let (data, response) = try await httpClient.data(for: request)
        try validate(response)
        return try decode([LRCLIBRecord].self, from: data)
    }

    private func bestRecord(for track: TrackMetadata, records: [LRCLIBRecord]) -> LRCLIBRecord? {
        var best: (record: LRCLIBRecord, score: Int)?

        for record in records {
            guard let syncedLyrics = record.syncedLyrics,
                  !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let candidate = record.trackMetadata
            guard let score = LyricsMatcher.score(track: track, candidate: candidate) else {
                continue
            }
            if best == nil || score > best!.score {
                best = (record, score)
            }
        }

        return best?.record
    }

    private func lyrics(from record: LRCLIBRecord) -> Lyrics? {
        guard let syncedLyrics = record.syncedLyrics,
              !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let lyrics = LRCParser().parse(syncedLyrics)
        return lyrics.lines.isEmpty ? nil : lyrics
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems
        guard let url = components?.url else { throw LRCLIBError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard response.statusCode == 200 else {
            throw LRCLIBError.httpStatus(response.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw LRCLIBError.invalidPayload
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private struct LRCLIBRecord: Decodable, Sendable {
        let id: Int?
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: TimeInterval?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?

        var trackMetadata: TrackMetadata {
            TrackMetadata(
                title: trackName,
                artist: artistName,
                album: albumName,
                duration: duration
            )
        }
    }
}

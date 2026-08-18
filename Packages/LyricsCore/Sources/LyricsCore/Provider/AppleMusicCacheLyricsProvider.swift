import Foundation

protocol AppleMusicCacheRetrySleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

private struct ContinuousCacheRetrySleeper: AppleMusicCacheRetrySleeper {
    func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

/// 讀取 Music.app 已經下載到本機的 Apple Music 歌詞快取。
///
/// 這個 provider 不會發出網路請求，也不會讀取 Apple 帳號憑證。Apple Music
/// 開啟某首歌的歌詞後，對應的 `syllable-lyrics` 回應會出現在這個快取中。
public struct AppleMusicCacheLyricsProvider: LyricsProvider, @unchecked Sendable {
    private let fileManager: FileManager
    private let cacheRoot: URL
    private let maximumCandidates: Int
    private let retryDelays: [Duration]
    private let retrySleeper: any AppleMusicCacheRetrySleeper

    public init(
        cacheRoot: URL? = nil,
        fileManager: FileManager = .default,
        maximumCandidates: Int = 160
    ) {
        self.fileManager = fileManager
        self.cacheRoot = cacheRoot ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.apple.Music", isDirectory: true)
        self.maximumCandidates = maximumCandidates
        self.retryDelays = Array(repeating: .milliseconds(300), count: 4)
        self.retrySleeper = ContinuousCacheRetrySleeper()
    }

    init(
        cacheRoot: URL,
        fileManager: FileManager = .default,
        maximumCandidates: Int = 160,
        retryDelays: [Duration],
        retrySleeper: any AppleMusicCacheRetrySleeper
    ) {
        self.fileManager = fileManager
        self.cacheRoot = cacheRoot
        self.maximumCandidates = maximumCandidates
        self.retryDelays = retryDelays
        self.retrySleeper = retrySleeper
    }

    public func lyrics(for track: TrackMetadata) async throws -> Lyrics? {
        if let lyrics = lookup(track: track) {
            return lyrics
        }

        for delay in retryDelays {
            try await retrySleeper.sleep(for: delay)
            if let lyrics = lookup(track: track) {
                return lyrics
            }
        }

        return nil
    }

    private func lookup(track: TrackMetadata) -> Lyrics? {
        var best: (score: Int, lyrics: Lyrics)?

        for candidate in candidates() {
            guard let data = candidate.data(using: fileManager),
                  let response = try? JSONDecoder().decode(CatalogResponse.self, from: data) else {
                continue
            }

            for song in response.data {
                guard let ttml = song.lyricsTTML,
                      let score = LyricsMatcher.score(
                          track: track,
                          candidate: song.metadata
                      ),
                      let lyrics = AppleMusicTTMLParser.parse(ttml) else {
                    continue
                }

                if best == nil || score > best!.score {
                    best = (score: score, lyrics: lyrics)
                }
            }

            if best?.score ?? 0 >= 260 {
                break
            }
        }

        return best?.lyrics
    }

    private func candidates() -> [CacheCandidate] {
        let indexed = indexedCandidates()
        var result = indexed
        var indexedPaths = Set(indexed.compactMap(\.fileURL))
        let directory = cacheRoot.appendingPathComponent("fsCachedData", isDirectory: true)
        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isRegularFileKey
        ]

        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }

        let recentFiles = files
            .filter {
                (try? $0.resourceValues(forKeys: resourceKeys).isRegularFile) == true
            }
            .sorted {
                let lhs = try? $0.resourceValues(forKeys: resourceKeys).contentModificationDate
                let rhs = try? $1.resourceValues(forKeys: resourceKeys).contentModificationDate
                return (lhs ?? .distantPast) > (rhs ?? .distantPast)
            }
            .prefix(maximumCandidates)

        for file in recentFiles where indexedPaths.insert(file).inserted {
            result.append(.file(file))
        }
        return result
    }

    private func indexedCandidates() -> [CacheCandidate] {
        let databaseURL = cacheRoot.appendingPathComponent("Cache.db", isDirectory: false)
        guard fileManager.isReadableFile(atPath: databaseURL.path),
              fileManager.isExecutableFile(atPath: "/usr/bin/sqlite3") else {
            return []
        }

        let query = """
        SELECT d.isDataOnFS || char(9) || hex(d.receiver_data)
        FROM cfurl_cache_response r
        JOIN cfurl_cache_receiver_data d USING(entry_ID)
        WHERE r.request_key LIKE '%syllable-lyrics%'
        ORDER BY r.time_stamp DESC
        LIMIT \(maximumCandidates);
        """

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", databaseURL.path, query]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let raw = String(data: data, encoding: .utf8) else {
                return []
            }

            return raw.split(whereSeparator: \.isNewline).compactMap { row in
                let fields = row.split(separator: "\t", maxSplits: 1).map(String.init)
                guard fields.count == 2,
                      let payload = Data(hexEncoded: fields[1]) else {
                    return nil
                }

                if fields[0] == "1",
                   let name = String(data: payload, encoding: .utf8),
                   isSafeCacheFileName(name) {
                    return .file(
                        cacheRoot
                            .appendingPathComponent("fsCachedData", isDirectory: true)
                            .appendingPathComponent(name, isDirectory: false)
                    )
                }
                if fields[0] == "0" {
                    return .inline(payload)
                }
                return nil
            }
        } catch {
            return []
        }
    }

    private func isSafeCacheFileName(_ name: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        return name.count == 36 && name.unicodeScalars.allSatisfy(allowed.contains)
    }

    private enum CacheCandidate {
        case file(URL)
        case inline(Data)

        var fileURL: URL? {
            guard case let .file(url) = self else { return nil }
            return url
        }

        func data(using fileManager: FileManager) -> Data? {
            switch self {
            case let .file(url):
                guard fileManager.isReadableFile(atPath: url.path) else { return nil }
                return try? Data(contentsOf: url)
            case let .inline(data):
                return data
            }
        }
    }

    private struct CatalogResponse: Decodable {
        let data: [CatalogSong]
    }

    private struct CatalogSong: Decodable {
        let attributes: Attributes
        let relationships: Relationships?

        var metadata: TrackMetadata {
            TrackMetadata(
                title: attributes.name,
                artist: attributes.artistName,
                album: attributes.albumName,
                duration: attributes.durationInMillis.map { Double($0) / 1000 }
            )
        }

        var lyricsTTML: String? {
            relationships?.syllableLyrics?.data.first?.attributes.ttmlLocalizations.value
        }

        struct Attributes: Decodable {
            let name: String
            let artistName: String
            let albumName: String?
            let durationInMillis: Int?
        }

        struct Relationships: Decodable {
            let syllableLyrics: SyllableLyricsRelationship?

            enum CodingKeys: String, CodingKey {
                case syllableLyrics = "syllable-lyrics"
            }
        }
    }

    private struct SyllableLyricsRelationship: Decodable {
        let data: [SyllableLyrics]
    }

    private struct SyllableLyrics: Decodable {
        let attributes: Attributes

        struct Attributes: Decodable {
            let ttmlLocalizations: TTMLLocalizations
        }
    }

    private enum TTMLLocalizations: Decodable {
        case value(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .value(value)
                return
            }

            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Apple Music TTML string"
                )
            )
        }

        var value: String {
            switch self {
            case let .value(value): return value
            }
        }
    }
}

private extension Data {
    init?(hexEncoded string: String) {
        let characters = Array(string)
        guard characters.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: characters.count / 2)
        var index = 0
        while index < characters.count {
            let pair = String(characters[index...index + 1])
            guard let byte = UInt8(pair, radix: 16) else { return nil }
            data.append(byte)
            index += 2
        }
        self = data
    }
}

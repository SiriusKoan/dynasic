import CryptoKit
import Foundation

public actor LyricsCache {
    private static let currentSchemaVersion = 1

    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load(for track: TrackMetadata) -> Lyrics? {
        let url = cacheFileURL(for: track)
        guard let data = try? Data(contentsOf: url),
              let entry = try? decoder.decode(CacheEntry.self, from: data),
              entry.version == Self.currentSchemaVersion else {
            try? fileManager.removeItem(at: url)
            return nil
        }

        return entry.lyrics
    }

    @discardableResult
    public func store(
        _ lyrics: Lyrics,
        for track: TrackMetadata,
        provider: String = "lrclib",
        providerID: Int? = nil,
        retrievedAt: Date = Date()
    ) -> Bool {
        let entry = CacheEntry(
            version: Self.currentSchemaVersion,
            track: track,
            provider: provider,
            providerID: providerID,
            retrievedAt: retrievedAt,
            lyrics: lyrics
        )

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(entry)
            try data.write(to: cacheFileURL(for: track), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func remove(for track: TrackMetadata) {
        try? fileManager.removeItem(at: cacheFileURL(for: track))
    }

    public func cacheFileURL(for track: TrackMetadata) -> URL {
        directory.appendingPathComponent(Self.cacheKey(for: track) + ".json")
    }

    public nonisolated static func cacheKey(for track: TrackMetadata) -> String {
        let duration = track.duration.map { duration in
            guard duration.isFinite else { return "none" }
            return String(Int(duration.rounded()))
        } ?? "none"
        let material = [
            normalized(track.artist),
            normalized(track.title),
            normalized(track.album ?? ""),
            duration
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("dynasic", isDirectory: true)
            .appendingPathComponent("Lyrics", isDirectory: true)
    }

    private static func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private struct CacheEntry: Codable, Sendable {
        let version: Int
        let track: TrackMetadata
        let provider: String
        let providerID: Int?
        let retrievedAt: Date
        let lyrics: Lyrics
    }
}

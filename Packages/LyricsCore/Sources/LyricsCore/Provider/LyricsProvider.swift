public protocol LyricsProvider: Sendable {
    func lyrics(for track: TrackMetadata) async throws -> Lyrics?
}

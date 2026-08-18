public struct LyricsProviderChain: LyricsProvider, Sendable {
    private let providers: [any LyricsProvider]

    public init(providers: [any LyricsProvider]) {
        self.providers = providers
    }

    public func lyrics(for track: TrackMetadata) async throws -> Lyrics? {
        for provider in providers {
            do {
                if let lyrics = try await provider.lyrics(for: track) {
                    return lyrics
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

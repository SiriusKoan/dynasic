public struct LyricsMetadata: Sendable, Equatable, Hashable {
    public let artist: String?
    public let album: String?
    public let title: String?
    public let offsetMilliseconds: Int?

    public init(
        artist: String? = nil,
        album: String? = nil,
        title: String? = nil,
        offsetMilliseconds: Int? = nil
    ) {
        self.artist = artist
        self.album = album
        self.title = title
        self.offsetMilliseconds = offsetMilliseconds
    }
}

public struct Lyrics: Sendable, Equatable {
    public let lines: [LyricLine]
    public let metadata: LyricsMetadata

    public init(lines: [LyricLine], metadata: LyricsMetadata = LyricsMetadata()) {
        self.lines = lines
        self.metadata = metadata
    }
}

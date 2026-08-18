import Foundation

public struct TrackMetadata: Sendable, Equatable, Hashable {
    public let title: String
    public let artist: String
    public let album: String?
    public let duration: TimeInterval?
    public let persistentID: String?

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval? = nil,
        persistentID: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.persistentID = persistentID
    }
}

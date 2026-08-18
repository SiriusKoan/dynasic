import Foundation

public struct LyricLine: Sendable, Equatable, Hashable {
    public let timestamp: TimeInterval
    public let text: String

    public init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

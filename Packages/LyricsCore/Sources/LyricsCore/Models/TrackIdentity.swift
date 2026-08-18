import Foundation

public struct TrackIdentity: Sendable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public init(metadata: TrackMetadata) {
        if let persistentID = Self.normalizedText(metadata.persistentID), !persistentID.isEmpty {
            self.rawValue = "persistent:\(Self.encoded(persistentID))"
            return
        }

        let duration = Self.durationToken(metadata.duration)
        self.rawValue = [
            "metadata",
            Self.encoded(Self.normalizedText(metadata.title) ?? ""),
            Self.encoded(Self.normalizedText(metadata.artist) ?? ""),
            Self.encoded(Self.normalizedText(metadata.album) ?? ""),
            Self.encoded(duration)
        ].joined(separator: "|")
    }

    public var description: String { rawValue }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }

        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func durationToken(_ duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite, duration >= 0 else {
            return "none"
        }

        // Apple Music 對同一首歌曲可能回傳略有差異的 duration。
        // 使用兩秒分桶吸收觀測誤差，同時保留 duration 作為備援識別依據。
        return String(Int((duration / 2).rounded()))
    }

    private static func encoded(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }
}

import Foundation

public struct LyricsMatch: Sendable, Equatable {
    public let metadata: TrackMetadata
    public let score: Int

    public init(metadata: TrackMetadata, score: Int) {
        self.metadata = metadata
        self.score = score
    }
}

public enum LyricsMatcher {
    public static func score(track: TrackMetadata, candidate: TrackMetadata) -> Int? {
        guard titlesMatch(track.title, candidate.title),
              normalized(track.artist) == normalized(candidate.artist) else {
            return nil
        }

        var score = 200
        if let album = normalizedOptional(track.album),
           album == normalizedOptional(candidate.album) {
            score += 20
        }

        if let trackDuration = track.duration,
           let candidateDuration = candidate.duration,
           trackDuration.isFinite,
           candidateDuration.isFinite {
            let delta = abs(trackDuration - candidateDuration)
            if delta > 10 {
                return nil
            }
            if delta <= 1 {
                score += 40
            } else if delta <= 2 {
                score += 30
            } else if delta <= 5 {
                score += 10
            }
        }

        return score
    }

    public static func bestMatch(
        track: TrackMetadata,
        candidates: [TrackMetadata]
    ) -> LyricsMatch? {
        var bestMatch: LyricsMatch?

        for candidate in candidates {
            guard let score = score(track: track, candidate: candidate) else { continue }
            let match = LyricsMatch(metadata: candidate, score: score)
            if bestMatch == nil || score > bestMatch!.score {
                bestMatch = match
            }
        }

        return bestMatch
    }

    private static func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalized(value)
        return normalized.isEmpty ? nil : normalized
    }

    private static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }

        let leftParts = left.components(separatedBy: " - ")
        let rightParts = right.components(separatedBy: " - ")
        return leftParts.contains(right) || rightParts.contains(left)
    }
}

import Foundation

public struct LRCParser: Sendable {
    public init() {}

    public func parse(_ source: String) -> Lyrics {
        var metadata = LyricsMetadata()
        var parsedLines: [ParsedLine] = []
        var sourceOrder = 0

        for line in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(line)

            if let parsedMetadata = Self.parseMetadataLine(line) {
                switch parsedMetadata.key {
                case "ar":
                    metadata = LyricsMetadata(
                        artist: parsedMetadata.value,
                        album: metadata.album,
                        title: metadata.title,
                        offsetMilliseconds: metadata.offsetMilliseconds
                    )
                case "al":
                    metadata = LyricsMetadata(
                        artist: metadata.artist,
                        album: parsedMetadata.value,
                        title: metadata.title,
                        offsetMilliseconds: metadata.offsetMilliseconds
                    )
                case "ti":
                    metadata = LyricsMetadata(
                        artist: metadata.artist,
                        album: metadata.album,
                        title: parsedMetadata.value,
                        offsetMilliseconds: metadata.offsetMilliseconds
                    )
                case "offset":
                    metadata = LyricsMetadata(
                        artist: metadata.artist,
                        album: metadata.album,
                        title: metadata.title,
                        offsetMilliseconds: Int(parsedMetadata.value)
                    )
                default:
                    break
                }
                continue
            }

            var cursor = line.startIndex
            var timestamps: [TimeInterval] = []

            while cursor < line.endIndex, line[cursor] == "[" {
                guard let closingBracket = line[cursor...].firstIndex(of: "]") else {
                    timestamps.removeAll()
                    break
                }

                let contentStart = line.index(after: cursor)
                let content = String(line[contentStart..<closingBracket])
                guard let timestamp = Self.parseTimestamp(content) else {
                    break
                }

                timestamps.append(timestamp)
                cursor = line.index(after: closingBracket)
            }

            guard !timestamps.isEmpty else { continue }

            let text = String(line[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
            for timestamp in timestamps {
                parsedLines.append(
                    ParsedLine(
                        line: LyricLine(timestamp: timestamp, text: text),
                        sourceOrder: sourceOrder
                    )
                )
                sourceOrder += 1
            }
        }

        let lines = parsedLines
            .sorted {
                if $0.line.timestamp == $1.line.timestamp {
                    return $0.sourceOrder < $1.sourceOrder
                }
                return $0.line.timestamp < $1.line.timestamp
            }
            .map(\.line)

        return Lyrics(lines: lines, metadata: metadata)
    }

    private static func parseTimestamp(_ content: String) -> TimeInterval? {
        let components = content.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
              let minutes = Int(components[0]),
              let seconds = Double(components[1]),
              minutes >= 0,
              seconds.isFinite,
              seconds >= 0,
              seconds < 60 else {
            return nil
        }

        return TimeInterval(minutes * 60) + seconds
    }

    private static func parseMetadataLine(_ line: String) -> (key: String, value: String)? {
        guard line.first == "[",
              let closingBracket = line.firstIndex(of: "]") else {
            return nil
        }

        let contentStart = line.index(after: line.startIndex)
        let content = String(line[contentStart..<closingBracket])
        guard let separator = content.firstIndex(of: ":") else { return nil }

        let key = String(content[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["ar", "al", "ti", "offset"].contains(key) else { return nil }

        let valueStart = content.index(after: separator)
        let value = String(content[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, value)
    }

    private struct ParsedLine: Sendable {
        let line: LyricLine
        let sourceOrder: Int
    }
}

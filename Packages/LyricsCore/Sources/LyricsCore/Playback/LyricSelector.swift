import Foundation

public struct LyricSelection: Sendable, Equatable {
    public let previous: LyricLine?
    public let current: LyricLine?
    public let next: LyricLine?
    public let currentIndex: Int?

    public init(
        previous: LyricLine?,
        current: LyricLine?,
        next: LyricLine?,
        currentIndex: Int?
    ) {
        self.previous = previous
        self.current = current
        self.next = next
        self.currentIndex = currentIndex
    }
}

public enum LyricSelector {
    public static func select(
        lines: [LyricLine],
        position: TimeInterval,
        offset: TimeInterval = 0
    ) -> LyricSelection {
        guard !lines.isEmpty,
              position.isFinite,
              offset.isFinite else {
            return emptySelection()
        }

        // offset 代表加到 lyric timestamp 的秒數，因此比較時從播放位置扣除。
        let adjustedPosition = position - offset
        var lowerBound = 0
        var upperBound = lines.count

        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if lines[middle].timestamp <= adjustedPosition {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let currentIndex = lowerBound - 1
        guard currentIndex >= 0 else {
            return LyricSelection(
                previous: nil,
                current: nil,
                next: lines.first,
                currentIndex: nil
            )
        }

        let nextIndex = currentIndex + 1
        return LyricSelection(
            previous: currentIndex > 0 ? lines[currentIndex - 1] : nil,
            current: lines[currentIndex],
            next: nextIndex < lines.count ? lines[nextIndex] : nil,
            currentIndex: currentIndex
        )
    }

    public static func select(
        lyrics: Lyrics,
        position: TimeInterval
    ) -> LyricSelection {
        let offset = Double(lyrics.metadata.offsetMilliseconds ?? 0) / 1000
        return select(lines: lyrics.lines, position: position, offset: offset)
    }

    private static func emptySelection() -> LyricSelection {
        LyricSelection(previous: nil, current: nil, next: nil, currentIndex: nil)
    }
}

import Foundation
import Testing

@testable import LyricsCore

private let selectorLines = [
    LyricLine(timestamp: 10, text: "A"),
    LyricLine(timestamp: 20, text: "B"),
    LyricLine(timestamp: 30, text: "C")
]

@Test
func selectorUsesExpectedTimestampBoundaries() {
    let beforeFirst = LyricSelector.select(lines: selectorLines, position: 9.999)
    let first = LyricSelector.select(lines: selectorLines, position: 10)
    let between = LyricSelector.select(lines: selectorLines, position: 19.999)
    let second = LyricSelector.select(lines: selectorLines, position: 20)
    let afterLast = LyricSelector.select(lines: selectorLines, position: 100)

    #expect(beforeFirst.current == nil)
    #expect(beforeFirst.next?.text == "A")
    #expect(first.current?.text == "A")
    #expect(first.currentIndex == 0)
    #expect(between.current?.text == "A")
    #expect(second.current?.text == "B")
    #expect(second.previous?.text == "A")
    #expect(afterLast.current?.text == "C")
    #expect(afterLast.next == nil)
}

@Test
func selectorAppliesTimestampOffset() {
    let selection = LyricSelector.select(
        lines: selectorLines,
        position: 11,
        offset: 1
    )

    #expect(selection.current?.text == "A")
}

@Test
func selectorUsesLyricsMetadataOffset() {
    let lyrics = Lyrics(
        lines: selectorLines,
        metadata: LyricsMetadata(offsetMilliseconds: 1_000)
    )

    #expect(LyricSelector.select(lyrics: lyrics, position: 11).current?.text == "A")
    #expect(LyricSelector.select(lyrics: lyrics, position: 10.999).current == nil)
}

@Test
func selectorHandlesEmptyAndInvalidPosition() {
    let empty = LyricSelector.select(lines: [], position: 10)
    let invalid = LyricSelector.select(lines: selectorLines, position: .nan)

    #expect(empty == LyricSelection(previous: nil, current: nil, next: nil, currentIndex: nil))
    #expect(invalid == empty)
}

@Test
func selectorPreservesDuplicateTimestampOrder() {
    let lines = [
        LyricLine(timestamp: 10, text: "first"),
        LyricLine(timestamp: 10, text: "second"),
        LyricLine(timestamp: 20, text: "third")
    ]

    let selection = LyricSelector.select(lines: lines, position: 10)

    #expect(selection.current?.text == "second")
    #expect(selection.previous?.text == "first")
    #expect(selection.next?.text == "third")
}

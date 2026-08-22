import Foundation
import Testing

@testable import LyricsCore

@Test
func waveformBucketContainsTwentyFourClampedFrequencyLevels() {
    let bucket = WaveformBucket(levels: [-1, .nan] + Array(repeating: 2, count: 30))

    #expect(bucket.levels.count == 24)
    #expect(bucket.levels[0] == 0)
    #expect(bucket.levels[1] == 0)
    #expect(bucket.levels.dropFirst(2).allSatisfy { $0 == 1 })
}

@Test
func waveformSpectrumKeepsFrequencyBinsIndependent() {
    var processor = WaveformSpectrumProcessor()
    var levels = Array(repeating: Float.zero, count: WaveformFrame.levelCount)
    levels[7] = 1

    let frame = processor.consume(WaveformBucket(levels: levels))

    #expect(frame.levels[7] > 0.4)
    #expect(frame.levels.enumerated().allSatisfy { index, level in
        index == 7 || level == 0
    })
}

@Test
func waveformAttackRisesFasterThanReleaseFalls() {
    let loud = WaveformBucket(levels: Array(repeating: 1, count: 24))
    let silent = WaveformBucket(levels: Array(repeating: 0, count: 24))
    var attackProcessor = WaveformSpectrumProcessor()
    let attacked = attackProcessor.consume(loud).levels[0]

    var releaseProcessor = WaveformSpectrumProcessor()
    for _ in 0..<24 {
        _ = releaseProcessor.consume(loud)
    }
    let beforeRelease = releaseProcessor.consume(loud).levels[0]
    let afterRelease = releaseProcessor.consume(silent).levels[0]

    #expect(attacked > 0.4)
    #expect(beforeRelease - afterRelease < attacked)
}

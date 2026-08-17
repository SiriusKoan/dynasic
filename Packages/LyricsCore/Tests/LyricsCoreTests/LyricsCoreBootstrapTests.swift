import Testing

@testable import LyricsCore

@Test
func packageLoads() {
    #expect(LyricsCore.packageVersion == "0.1.0")
}

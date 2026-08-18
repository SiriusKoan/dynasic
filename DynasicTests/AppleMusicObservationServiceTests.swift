import XCTest
import LyricsCore

@testable import dynasic

final class AppleMusicObservationServiceTests: XCTestCase {
    func testParsesPlayingTrackSnapshot() async throws {
        let runner = StubScriptRunner(output: """
        state=playing
        title=Midnight City
        artist=M83
        album=Hurry Up, We're Dreaming
        duration=243.2
        position=12.5
        persistent-id=123456789
        """)
        let service = AppleMusicObservationService(scriptRunner: runner)

        let snapshot = try await service.snapshot()

        XCTAssertEqual(snapshot.state, .playing)
        XCTAssertEqual(snapshot.position, 12.5)
        XCTAssertEqual(
            snapshot.track,
            TrackMetadata(
                title: "Midnight City",
                artist: "M83",
                album: "Hurry Up, We're Dreaming",
                duration: 243.2,
                persistentID: "123456789"
            )
        )
        XCTAssertGreaterThanOrEqual(snapshot.observationLatency, 0)
    }

    func testTrackErrorProducesSnapshotWithoutTrack() async throws {
        let runner = StubScriptRunner(output: """
        state=paused
        position=33.0
        track-error=-1728:No current track
        """)
        let service = AppleMusicObservationService(scriptRunner: runner)

        let snapshot = try await service.snapshot()

        XCTAssertEqual(snapshot.state, .paused)
        XCTAssertEqual(snapshot.position, 33.0)
        XCTAssertNil(snapshot.track)
    }

    func testMalformedResponseIsRejected() async {
        let runner = StubScriptRunner(output: "title=Missing State")
        let service = AppleMusicObservationService(scriptRunner: runner)

        do {
            _ = try await service.snapshot()
            XCTFail("Expected malformed response to be rejected")
        } catch let error as AppleMusicObservationError {
            XCTAssertEqual(error, .invalidResponse("missing state"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct StubScriptRunner: AppleMusicScriptRunner {
    let output: String

    func run() throws -> String {
        output
    }
}

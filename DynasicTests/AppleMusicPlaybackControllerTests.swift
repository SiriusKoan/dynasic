import Foundation
import XCTest

@testable import dynasic

final class AppleMusicPlaybackControllerTests: XCTestCase {
    func testAppleScriptMapsAllPlaybackCommands() {
        let expected: [(PlaybackControlCommand, String)] = [
            (.previousTrack, "previous track"),
            (.playPause, "playpause"),
            (.nextTrack, "next track")
        ]

        for (command, statement) in expected {
            XCTAssertEqual(command.appleScriptStatement, statement)
            XCTAssertTrue(SystemAppleMusicControlScriptRunner.source(for: command).contains(statement))
        }
    }

    func testControllerForwardsCommandToScriptRunner() async throws {
        let runner = RecordingPlaybackControlScriptRunner()
        let controller = AppleMusicPlaybackController(scriptRunner: runner)

        try await controller.perform(.nextTrack)

        XCTAssertEqual(runner.commands, [.nextTrack])
    }
}

private final class RecordingPlaybackControlScriptRunner: PlaybackControlScriptRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCommands: [PlaybackControlCommand] = []

    var commands: [PlaybackControlCommand] {
        lock.withLock { recordedCommands }
    }

    func run(command: PlaybackControlCommand) throws {
        lock.withLock {
            recordedCommands.append(command)
        }
    }
}

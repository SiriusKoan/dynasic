import AppKit
import Foundation

enum PlaybackControlCommand: CaseIterable, Equatable, Sendable {
    case previousTrack
    case playPause
    case nextTrack

    var appleScriptStatement: String {
        switch self {
        case .previousTrack:
            return "previous track"
        case .playPause:
            return "playpause"
        case .nextTrack:
            return "next track"
        }
    }
}

enum PlaybackControlError: Error, Equatable, Sendable {
    case scriptUnavailable
    case scriptFailed(String)
}

protocol PlaybackControlScriptRunner: Sendable {
    func run(command: PlaybackControlCommand) throws
}

struct SystemAppleMusicControlScriptRunner: PlaybackControlScriptRunner {
    func run(command: PlaybackControlCommand) throws {
        guard let script = NSAppleScript(source: Self.source(for: command)) else {
            throw PlaybackControlError.scriptUnavailable
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw PlaybackControlError.scriptFailed(errorInfo.description)
        }
    }

    static func source(for command: PlaybackControlCommand) -> String {
        #"""
        try
            tell application "/System/Applications/Music.app"
                \#(command.appleScriptStatement)
            end tell
        on error messageText number numberValue
            error messageText number numberValue
        end try
        """#
    }
}

protocol PlaybackControlling: Sendable {
    func perform(_ command: PlaybackControlCommand) async throws
}

struct AppleMusicPlaybackController: PlaybackControlling, Sendable {
    private let scriptRunner: any PlaybackControlScriptRunner

    init(scriptRunner: any PlaybackControlScriptRunner = SystemAppleMusicControlScriptRunner()) {
        self.scriptRunner = scriptRunner
    }

    func perform(_ command: PlaybackControlCommand) async throws {
        let scriptRunner = self.scriptRunner
        try await Task.detached(priority: .userInitiated) {
            try scriptRunner.run(command: command)
        }.value
    }
}

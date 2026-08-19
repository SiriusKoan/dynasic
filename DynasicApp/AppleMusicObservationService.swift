import AppKit
import Foundation
import LyricsCore

enum AppleMusicObservationError: Error, Equatable, Sendable {
    case scriptUnavailable
    case scriptFailed(String)
    case invalidResponse(String)
}

protocol AppleMusicScriptRunner: Sendable {
    func run() throws -> String
}

struct SystemAppleMusicScriptRunner: AppleMusicScriptRunner {
    private static let source = #"""
    try
        tell application "/System/Applications/Music.app"
            set stateText to (player state as text)
            set positionText to (player position as text)
            try
                set currentTrack to current track
                set titleText to (name of currentTrack as text)
                set artistText to (artist of currentTrack as text)
                set albumText to (album of currentTrack as text)
                set durationText to (duration of currentTrack as text)
                set persistentIDText to (persistent ID of currentTrack as text)
                return "state=" & stateText & linefeed & ¬
                    "title=" & titleText & linefeed & ¬
                    "artist=" & artistText & linefeed & ¬
                    "album=" & albumText & linefeed & ¬
                    "duration=" & durationText & linefeed & ¬
                    "position=" & positionText & linefeed & ¬
                    "persistent-id=" & persistentIDText
            on error trackMessage number trackNumber
                return "state=" & stateText & linefeed & ¬
                    "position=" & positionText & linefeed & ¬
                    "track-error=" & (trackNumber as text) & ":" & trackMessage
            end try
        end tell
    on error messageText number numberValue
        return "error=" & (numberValue as text) & ":" & messageText
    end try
    """#

    func run() throws -> String {
        guard let script = NSAppleScript(source: Self.source) else {
            throw AppleMusicObservationError.scriptUnavailable
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw AppleMusicObservationError.scriptFailed(errorInfo.description)
        }
        return descriptor.stringValue ?? descriptor.description
    }
}

struct AppleMusicObservationService: AppleMusicObservationBackend, Sendable {
    private let scriptRunner: any AppleMusicScriptRunner
    private let timeSource: any MonotonicTimeSource

    init(
        scriptRunner: any AppleMusicScriptRunner = SystemAppleMusicScriptRunner(),
        timeSource: any MonotonicTimeSource = ContinuousClockTimeSource()
    ) {
        self.scriptRunner = scriptRunner
        self.timeSource = timeSource
    }

    func snapshot() async throws -> PlaybackSnapshot {
        let scriptRunner = self.scriptRunner
        let startedAt = timeSource.now()
        let output = try await Task.detached(priority: .utility) {
            try scriptRunner.run()
        }.value
        let observationLatency = max(0, timeSource.now() - startedAt)
        return try Self.parse(output, observationLatency: observationLatency)
    }

    private static func parse(
        _ output: String,
        observationLatency: TimeInterval
    ) throws -> PlaybackSnapshot {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1])
        }

        if let error = values["error"] {
            throw AppleMusicObservationError.scriptFailed(error)
        }

        guard let stateValue = values["state"]?.lowercased() else {
            throw AppleMusicObservationError.invalidResponse("missing state")
        }

        let state: PlaybackState
        switch stateValue {
        case "playing":
            state = .playing
        case "paused":
            state = .paused
        case "stopped":
            state = .stopped
        default:
            throw AppleMusicObservationError.invalidResponse("unknown state: \(stateValue)")
        }

        let track: TrackMetadata?
        if let title = nonEmpty(values["title"]),
           let artist = nonEmpty(values["artist"]) {
            track = TrackMetadata(
                title: title,
                artist: artist,
                album: nonEmpty(values["album"]),
                duration: timeValue(values["duration"]),
                persistentID: nonEmpty(values["persistent-id"])
            )
        } else {
            track = nil
        }

        return PlaybackSnapshot(
            track: track,
            state: state,
            position: timeValue(values["position"]),
            observedAt: ContinuousClock().now,
            observationLatency: observationLatency
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func timeValue(_ value: String?) -> TimeInterval? {
        guard let value,
              let number = Double(value),
              number.isFinite,
              number >= 0 else {
            return nil
        }
        return number
    }
}

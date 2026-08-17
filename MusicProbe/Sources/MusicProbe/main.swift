import AppKit
import Combine
import Foundation
import SwiftUI

private struct ProbeField: Identifiable {
    let id: String
    let label: String
    var value: String
}

private struct MusicSnapshot {
    var values: [String: String]
    var error: String?
}

private enum MusicAppleEvents {
    static let source = #"""
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
                    "track-id=" & persistentIDText
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

    static func read() -> MusicSnapshot {
        guard let script = NSAppleScript(source: source) else {
            return MusicSnapshot(values: [:], error: "AppleScript compilation returned no script.")
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return MusicSnapshot(values: [:], error: errorInfo.description)
        }

        let output = descriptor.stringValue ?? descriptor.description
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1])
        }

        let error = values.removeValue(forKey: "error") ?? values.removeValue(forKey: "track-error")
        return MusicSnapshot(values: values, error: error)
    }
}

@MainActor
private final class ProbeModel: ObservableObject {
    @Published private(set) var fields: [ProbeField] = [
        ProbeField(id: "authorization", label: "Authorization", value: "Not requested"),
        ProbeField(id: "music", label: "Music running", value: "Unknown"),
        ProbeField(id: "state", label: "Playback state", value: "—"),
        ProbeField(id: "title", label: "Title", value: "—"),
        ProbeField(id: "artist", label: "Artist", value: "—"),
        ProbeField(id: "album", label: "Album", value: "—"),
        ProbeField(id: "duration", label: "Duration", value: "—"),
        ProbeField(id: "position", label: "Position", value: "—"),
        ProbeField(id: "track-id", label: "Track identifier", value: "Not exposed by probe"),
    ]
    @Published private(set) var lastUpdate = "Never"
    @Published private(set) var errorMessage = "None"

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let snapshot = MusicAppleEvents.read()
        let values = snapshot.values

        for index in fields.indices {
            if let value = values[fields[index].id] {
                fields[index].value = value
            }
        }

        fields[0].value = values["state"] == nil ? "Unavailable" : "Active"
        fields[1].value = snapshot.error == nil ? "Query completed" : "Query failed"
        lastUpdate = ISO8601DateFormatter().string(from: Date())
        errorMessage = snapshot.error ?? "None"
        print("[MusicProbe] \(lastUpdate) \(values.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")) error=\(errorMessage)")
    }
}

private struct ContentView: View {
    @ObservedObject var model: ProbeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MusicProbe")
                .font(.title2.weight(.semibold))

            Text("Apple Events observation • 1 Hz")
                .foregroundStyle(.secondary)

            Divider()

            ForEach(model.fields) { field in
                HStack {
                    Text(field.label)
                        .frame(width: 150, alignment: .leading)
                    Text(field.value)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 13, design: .monospaced))
            }

            Divider()

            Text("Last update: \(model.lastUpdate)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Error: \(model.errorMessage)")
                .font(.caption)
                .foregroundStyle(model.errorMessage == "None" ? Color.secondary : Color.red)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(width: 620, height: 470)
    }
}

@main
private struct MusicProbeApp: App {
    @StateObject private var model = ProbeModel()

    var body: some Scene {
        WindowGroup("MusicProbe") {
            ContentView(model: model)
        }
    }
}

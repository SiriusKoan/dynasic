import AppKit
import Foundation
import LyricsCore

enum AppleMusicArtworkError: Error, Equatable, Sendable {
    case scriptUnavailable
    case scriptFailed(String)
}

protocol AppleMusicArtworkScriptRunner: Sendable {
    func run(for track: TrackMetadata) throws -> Data?
}

struct SystemAppleMusicArtworkScriptRunner: AppleMusicArtworkScriptRunner {
    func run(for track: TrackMetadata) throws -> Data? {
        guard let script = NSAppleScript(source: Self.source) else {
            throw AppleMusicArtworkError.scriptUnavailable
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw AppleMusicArtworkError.scriptFailed(errorInfo.description)
        }

        let data = descriptor.data
        if !data.isEmpty, NSImage(data: data) == nil {
            let prefix = data.prefix(16).map { String(format: "%02x", $0) }.joined()
            let type = String(format: "%08x", descriptor.descriptorType)
            throw AppleMusicArtworkError.scriptFailed(
                "Unsupported artwork descriptor type=\(type) bytes=\(data.count) prefix=\(prefix)"
            )
        }
        return data.isEmpty ? nil : data
    }

    private static let source = """
        try
            tell application "/System/Applications/Music.app"
                if (count of artworks of current track) = 0 then return
                return data of artwork 1 of current track
            end tell
        on error messageText number numberValue
            error number numberValue
        end try
        """
}

protocol AppleMusicArtworkProviding: Sendable {
    func artwork(for track: TrackMetadata) async throws -> Data?
}

struct AppleMusicArtworkService: AppleMusicArtworkProviding, Sendable {
    private let scriptRunner: any AppleMusicArtworkScriptRunner

    init(scriptRunner: any AppleMusicArtworkScriptRunner = SystemAppleMusicArtworkScriptRunner()) {
        self.scriptRunner = scriptRunner
    }

    func artwork(for track: TrackMetadata) async throws -> Data? {
        let scriptRunner = self.scriptRunner
        return try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try scriptRunner.run(for: track)
        }.value
    }
}

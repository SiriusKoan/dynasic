import AppKit
import Foundation
import Combine
import LyricsCore

enum LyricsPanelAlignment: String, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    var id: Self { self }

    var title: String {
        switch self {
        case .leading:
            return "Leading"
        case .center:
            return "Center"
        case .trailing:
            return "Trailing"
        }
    }
}

@MainActor
final class DynasicAppState: ObservableObject {
    @Published private(set) var viewState: LyricsViewState = .idle
    @Published private(set) var estimatedPlaybackPosition: TimeInterval?
    @Published private(set) var musicBackendStatus = "not started"
    @Published private(set) var reportedPlaybackState: PlaybackState?
    @Published private(set) var reportedPlaybackPosition: TimeInterval?
    @Published private(set) var lastSnapshotAt: Date?
    @Published private(set) var lastObservationError: String?
    @Published var isLyricsVisible = false
    @Published var lyricsOffset: Double {
        didSet { userDefaults.set(lyricsOffset, forKey: SettingKey.lyricsOffset) }
    }
    @Published var lyricsFontSize: Double {
        didSet { userDefaults.set(lyricsFontSize, forKey: SettingKey.lyricsFontSize) }
    }
    @Published var lyricsOpacity: Double {
        didSet { userDefaults.set(lyricsOpacity, forKey: SettingKey.lyricsOpacity) }
    }
    @Published var lyricsAlignment: LyricsPanelAlignment {
        didSet { userDefaults.set(lyricsAlignment.rawValue, forKey: SettingKey.lyricsAlignment) }
    }
    @Published var isClickThrough: Bool {
        didSet {
            userDefaults.set(isClickThrough, forKey: SettingKey.isClickThrough)
            panelController?.setClickThrough(isClickThrough)
        }
    }
    @Published var isAlwaysOnTop: Bool {
        didSet {
            userDefaults.set(isAlwaysOnTop, forKey: SettingKey.isAlwaysOnTop)
            panelController?.setAlwaysOnTop(isAlwaysOnTop)
        }
    }
    @Published var showsPreviousLine: Bool {
        didSet { userDefaults.set(showsPreviousLine, forKey: SettingKey.showsPreviousLine) }
    }
    @Published var showsNextLine: Bool {
        didSet { userDefaults.set(showsNextLine, forKey: SettingKey.showsNextLine) }
    }

    let coordinator: LyricsCoordinator
    private let userDefaults: UserDefaults
    private let musicBackend: any AppleMusicObservationBackend
    private var observationTask: Task<Void, Never>?
    private var panelController: LyricsPanelController?
    private var mainWindowController: MainWindowController?

    var panelControllerForTesting: LyricsPanelController? { panelController }
    var mainWindowControllerForTesting: MainWindowController? { mainWindowController }

    init(
        userDefaults: UserDefaults = .standard,
        musicBackend: any AppleMusicObservationBackend = AppleMusicObservationService(),
        startImmediately: Bool = false
    ) {
        self.userDefaults = userDefaults
        self.musicBackend = musicBackend
        userDefaults.register(defaults: [
            SettingKey.lyricsOffset: 0.0,
            SettingKey.lyricsFontSize: 22.0,
            SettingKey.lyricsOpacity: 1.0,
            SettingKey.lyricsAlignment: LyricsPanelAlignment.center.rawValue,
            SettingKey.isClickThrough: false,
            SettingKey.isAlwaysOnTop: true,
            SettingKey.showsPreviousLine: true,
            SettingKey.showsNextLine: true
        ])

        _lyricsOffset = Published(initialValue: userDefaults.double(forKey: SettingKey.lyricsOffset))
        _lyricsFontSize = Published(initialValue: userDefaults.double(forKey: SettingKey.lyricsFontSize))
        _lyricsOpacity = Published(initialValue: userDefaults.double(forKey: SettingKey.lyricsOpacity))
        _lyricsAlignment = Published(
            initialValue: LyricsPanelAlignment(
                rawValue: userDefaults.string(forKey: SettingKey.lyricsAlignment) ?? ""
            ) ?? .center
        )
        _isClickThrough = Published(initialValue: userDefaults.bool(forKey: SettingKey.isClickThrough))
        _isAlwaysOnTop = Published(initialValue: userDefaults.bool(forKey: SettingKey.isAlwaysOnTop))
        _showsPreviousLine = Published(initialValue: userDefaults.bool(forKey: SettingKey.showsPreviousLine))
        _showsNextLine = Published(initialValue: userDefaults.bool(forKey: SettingKey.showsNextLine))
        _estimatedPlaybackPosition = Published(initialValue: nil)

        let provider = LyricsProviderChain(providers: [
            AppleMusicCacheLyricsProvider(),
            LRCLIBProvider(httpClient: URLSessionHTTPClient())
        ])
        coordinator = LyricsCoordinator(
            provider: provider,
            cache: LyricsCache()
        )

        if startImmediately {
            startObservation()
        }
    }

    deinit {
        observationTask?.cancel()
    }

    func showLyrics() {
        isLyricsVisible = true
        if panelController == nil {
            panelController = LyricsPanelController(state: self)
        }
        panelController?.show()
    }

    func hideLyrics() {
        isLyricsVisible = false
        panelController?.hide()
    }

    func showMainWindow() {
        if mainWindowController?.window == nil {
            mainWindowController = MainWindowController(state: self)
        }
        mainWindowController?.show()
    }

    func startObservation() {
        guard observationTask == nil else { return }

        musicBackendStatus = "polling"
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.observeOnce()
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    break
                }
            }
        }
    }

    func stopObservation() {
        observationTask?.cancel()
        observationTask = nil
    }

    var isObservationRunning: Bool {
        observationTask != nil
    }

    func observeOnceForTesting() async {
        await observeOnce()
    }

    func refreshViewState() {
        Task { [weak self, coordinator] in
            let state = await coordinator.currentState()
            let position = await coordinator.currentPosition()
            self?.viewState = state
            self?.estimatedPlaybackPosition = position
        }
    }

    private func observeOnce() async {
        do {
            let snapshot = try await musicBackend.snapshot()
            reportedPlaybackState = snapshot.state
            reportedPlaybackPosition = snapshot.position
            lastSnapshotAt = Date()
            lastObservationError = nil
            musicBackendStatus = "connected"

            await coordinator.process(snapshot: snapshot)
            viewState = await coordinator.currentState()
            estimatedPlaybackPosition = await coordinator.currentPosition()
        } catch {
            musicBackendStatus = "unavailable"
            lastObservationError = String(describing: error)
            viewState = .musicUnavailable
            estimatedPlaybackPosition = nil
        }
    }

    var trackTitle: String {
        switch viewState {
        case let .loading(track), let .noLyrics(track):
            return track.title
        case let .displaying(track, _, _):
            return track.title
        default:
            return "Nothing Playing"
        }
    }

    var trackArtist: String {
        switch viewState {
        case let .loading(track), let .noLyrics(track):
            return track.artist
        case let .displaying(track, _, _):
            return track.artist
        default:
            return ""
        }
    }

    var diagnosticsText: String {
        let track = diagnosticTrack
        let lyrics = diagnosticLyrics
        let bundleInfo = Bundle.main.infoDictionary
        let version = bundleInfo?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundleInfo?["CFBundleVersion"] as? String ?? "unknown"
        let lineCount = lyrics.map { String($0.lineCount) } ?? "—"
        let currentIndex = lyrics.flatMap { $0.currentIndex.map(String.init) } ?? "—"

        return """
        Application
        -----------
        product: dynasic
        version: \(version)
        build: \(build)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        architecture: \(Self.architecture)

        Apple Music
        -----------
        backend: Apple Events
        authorization: usage description declared; TCC state not exposed
        Music running: \(musicBackendStatus)
        state: \(reportedPlaybackState.map(String.init(describing:)) ?? "—")

        Track
        -----
        title: \(track?.title ?? "—")
        artist: \(track?.artist ?? "—")
        album: \(track?.album ?? "—")
        duration: \(formatted(track?.duration))
        identity: \(track.map { TrackIdentity(metadata: $0).description } ?? "—")

        Playback
        --------
        reportedPosition: \(formatted(reportedPlaybackPosition))
        estimatedPosition: \(formatted(estimatedPlaybackPosition))
        drift: not exposed
        lastSnapshotAge: \(lastSnapshotAge)

        Lyrics
        ------
        provider: Apple Music cache → LRCLIB
        cache hit: unknown
        provider ID: not exposed
        line count: \(lineCount)
        currentIndex: \(currentIndex)
        offset: \(lyricsOffset)s
        fontSize: \(lyricsFontSize)
        opacity: \(lyricsOpacity)
        alignment: \(lyricsAlignment.rawValue)
        clickThrough: \(isClickThrough)
        alwaysOnTop: \(isAlwaysOnTop)
        showPreviousLine: \(showsPreviousLine)
        showNextLine: \(showsNextLine)

        Network
        -------
        last request: not exposed
        status: not exposed
        latency: not exposed

        Errors
        ------
        last error: \(diagnosticError)
        """
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText, forType: .string)
    }

    private var diagnosticTrack: TrackMetadata? {
        switch viewState {
        case let .loading(track), let .displaying(track, _, _), let .noLyrics(track):
            return track
        case .idle, .musicUnavailable, .nothingPlaying, .error:
            return nil
        }
    }

    private var diagnosticLyrics: (lineCount: Int, currentIndex: Int?)? {
        guard case let .displaying(_, lyrics, currentIndex) = viewState else {
            return nil
        }
        return (lyrics.lines.count, currentIndex)
    }

    private var diagnosticError: String {
        if let lastObservationError {
            return lastObservationError
        }
        guard case let .error(error) = viewState else { return "None" }
        return String(describing: error)
    }

    private var lastSnapshotAge: String {
        guard let lastSnapshotAt else { return "—" }
        return String(format: "%.1f s", max(0, Date().timeIntervalSince(lastSnapshotAt)))
    }

    private func formatted(_ value: TimeInterval?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f s", value)
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private enum SettingKey {
        static let lyricsOffset = "dynasic.settings.lyricsOffset"
        static let lyricsFontSize = "dynasic.settings.lyricsFontSize"
        static let lyricsOpacity = "dynasic.settings.lyricsOpacity"
        static let lyricsAlignment = "dynasic.settings.lyricsAlignment"
        static let isClickThrough = "dynasic.settings.isClickThrough"
        static let isAlwaysOnTop = "dynasic.settings.isAlwaysOnTop"
        static let showsPreviousLine = "dynasic.settings.showsPreviousLine"
        static let showsNextLine = "dynasic.settings.showsNextLine"
    }
}

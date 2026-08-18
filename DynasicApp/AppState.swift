import AppKit
import Foundation
import Combine
import LyricsCore

@MainActor
final class DynasicAppState: ObservableObject {
    @Published private(set) var viewState: LyricsViewState = .idle
    @Published private(set) var estimatedPlaybackPosition: TimeInterval?
    @Published private(set) var musicBackendStatus = "not started"
    @Published private(set) var reportedPlaybackState: PlaybackState?
    @Published private(set) var reportedPlaybackPosition: TimeInterval?
    @Published private(set) var lastSnapshotAt: Date?
    @Published private(set) var lastObservationLatency: TimeInterval?
    @Published private(set) var lastObservationError: String?
    @Published var isLyricsVisible = false
    @Published var settings: DynasicSettings {
        didSet {
            settingsStore.save(settings)
            if settings.isClickThrough != oldValue.isClickThrough {
                panelController?.setClickThrough(settings.isClickThrough)
            }
            if settings.isAlwaysOnTop != oldValue.isAlwaysOnTop {
                panelController?.setAlwaysOnTop(settings.isAlwaysOnTop)
            }
        }
    }

    let coordinator: LyricsCoordinator
    private let settingsStore: DynasicSettingsStore
    private let musicBackend: any AppleMusicObservationBackend
    private let updateScheduler = AppUpdateScheduler()
    private var panelController: LyricsPanelController?
    private var mainWindowController: MainWindowController?

    var panelControllerForTesting: LyricsPanelController? { panelController }
    var mainWindowControllerForTesting: MainWindowController? { mainWindowController }

    init(
        userDefaults: UserDefaults = .standard,
        musicBackend: any AppleMusicObservationBackend = AppleMusicObservationService(),
        startImmediately: Bool = false
    ) {
        self.musicBackend = musicBackend
        let settingsStore = DynasicSettingsStore(userDefaults: userDefaults)
        self.settingsStore = settingsStore
        _settings = Published(initialValue: settingsStore.load())
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
        guard !updateScheduler.isRunning else { return }
        musicBackendStatus = "polling"
        updateScheduler.start(
            observe: { [weak self] in await self?.observeOnce() },
            refreshDisplay: { [weak self] in await self?.refreshViewStateNow() }
        )
    }

    func stopObservation() {
        updateScheduler.stop()
    }

    var isObservationRunning: Bool {
        updateScheduler.isRunning
    }

    func observeOnceForTesting() async {
        await observeOnce()
    }

    func refreshViewStateForTesting() async {
        await refreshViewStateNow()
    }

    func refreshViewState() {
        Task { [weak self] in
            await self?.refreshViewStateNow()
        }
    }

    private func refreshViewStateNow() async {
        guard musicBackendStatus != "unavailable" else { return }
        let state = await coordinator.currentState()
        let position = await coordinator.currentPosition()
        viewState = state
        estimatedPlaybackPosition = position
    }

    private func observeOnce() async {
        do {
            let snapshot = try await musicBackend.snapshot()
            reportedPlaybackState = snapshot.state
            reportedPlaybackPosition = snapshot.position
            lastObservationLatency = snapshot.observationLatency
            lastSnapshotAt = Date()
            lastObservationError = nil
            musicBackendStatus = "connected"

            await coordinator.process(snapshot: snapshot)
            await refreshViewStateNow()
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
        observationLatency: \(formatted(lastObservationLatency))
        drift: not exposed
        lastSnapshotAge: \(lastSnapshotAge)

        Lyrics
        ------
        provider: Apple Music cache → LRCLIB
        cache hit: unknown
        provider ID: not exposed
        line count: \(lineCount)
        currentIndex: \(currentIndex)
        offset: \(settings.lyricsOffset)s
        fontSize: \(settings.lyricsFontSize)
        opacity: \(settings.lyricsOpacity)
        alignment: \(settings.lyricsAlignment.rawValue)
        clickThrough: \(settings.isClickThrough)
        alwaysOnTop: \(settings.isAlwaysOnTop)
        showPreviousLine: \(settings.showsPreviousLine)
        showNextLine: \(settings.showsNextLine)

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

}

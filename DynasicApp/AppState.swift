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
    @Published private(set) var lastArtworkError: String?
    @Published private(set) var trackArtwork: NSImage?
    @Published private(set) var waveformState: WaveformCaptureState = .disabled
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
            if settings.isWaveformEnabled != oldValue.isWaveformEnabled {
                refreshWaveformCapture()
            }
        }
    }

    let coordinator: LyricsCoordinator
    private let settingsStore: DynasicSettingsStore
    private let musicBackend: any AppleMusicObservationBackend
    private let artworkProvider: any AppleMusicArtworkProviding
    private let waveformCoordinator: WaveformCoordinator
    private let updateScheduler = AppUpdateScheduler()
    private var artworkTrackIdentity: TrackIdentity?
    private var artworkCache: [TrackIdentity: NSImage] = [:]
    private var artworkTask: Task<Void, Never>?
    private var panelController: LyricsPanelController?

    var panelControllerForTesting: LyricsPanelController? { panelController }

    init(
        userDefaults: UserDefaults = .standard,
        musicBackend: any AppleMusicObservationBackend = AppleMusicObservationService(),
        artworkProvider: any AppleMusicArtworkProviding = AppleMusicArtworkService(),
        waveformSource: any WaveformSource = AppleMusicProcessTapWaveformSource(),
        waveformTimeSource: any MonotonicTimeSource = ContinuousClockTimeSource(),
        startImmediately: Bool = false
    ) {
        self.musicBackend = musicBackend
        self.artworkProvider = artworkProvider
        waveformCoordinator = WaveformCoordinator(
            source: waveformSource,
            timeSource: waveformTimeSource
        )
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
        waveformCoordinator.onStateChange = { [weak self] state in
            self?.waveformState = state
        }

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
        refreshWaveformCapture()
    }

    func hideLyrics() {
        isLyricsVisible = false
        panelController?.hide()
        refreshWaveformCapture()
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

    func shutdown() async {
        stopObservation()
        await waveformCoordinator.shutdown()
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

    func waitForArtworkForTesting() async {
        await artworkTask?.value
    }

    func refreshViewState() {
        Task { [weak self] in
            await self?.refreshViewStateNow()
        }
    }

    private func refreshViewStateNow() async {
        guard musicBackendStatus != "unavailable" else { return }
        let display = await coordinator.currentDisplay()
        viewState = display.state
        estimatedPlaybackPosition = display.position
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
            updateArtwork(for: snapshot.track)
            refreshWaveformCapture()
        } catch {
            musicBackendStatus = "unavailable"
            lastObservationError = String(describing: error)
            viewState = .musicUnavailable
            estimatedPlaybackPosition = nil
            reportedPlaybackState = nil
            updateArtwork(for: nil)
            refreshWaveformCapture()
        }
    }

    func refreshWaveformCapture() {
        waveformCoordinator.reconcile(
            enabled: settings.isWaveformEnabled,
            panelVisible: panelController?.isVisible == true,
            collapsed: panelController?.isCollapsed == true,
            playbackState: reportedPlaybackState
        )
    }

    func waitForWaveformLifecycleForTesting() async {
        await waveformCoordinator.waitForLifecycleForTesting()
    }

    private func updateArtwork(for track: TrackMetadata?) {
        let identity = track.map(TrackIdentity.init(metadata:))
        guard identity != artworkTrackIdentity else { return }

        artworkTask?.cancel()
        artworkTask = nil
        artworkTrackIdentity = identity
        trackArtwork = nil
        lastArtworkError = nil

        guard let track, let identity else { return }

        if let cachedArtwork = artworkCache[identity] {
            trackArtwork = cachedArtwork
            return
        }

        let artworkProvider = self.artworkProvider
        artworkTask = Task { @MainActor [weak self] in
            do {
                let data = try await artworkProvider.artwork(for: track)
                guard !Task.isCancelled else { return }
                let image = data.flatMap(NSImage.init(data:))
                guard let self, self.artworkTrackIdentity == identity else { return }
                if let image {
                    self.artworkCache[identity] = image
                    self.lastArtworkError = nil
                } else if let data {
                    self.lastArtworkError = "Artwork data could not be decoded (\(data.count) bytes)"
                } else {
                    self.lastArtworkError = "Apple Music returned no artwork data"
                }
                self.trackArtwork = image
                self.artworkTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.artworkTrackIdentity == identity else { return }
                self.trackArtwork = nil
                self.lastArtworkError = String(describing: error)
                self.artworkTask = nil
            }
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

    var trackDuration: TimeInterval? {
        diagnosticTrack?.duration
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
        layout: \(settings.lyricsPanelLayout.rawValue)
        clickThrough: \(settings.isClickThrough)
        alwaysOnTop: \(settings.isAlwaysOnTop)
        lyricsWindowStickyToEdges: \(settings.isLyricsWindowStickyToEdges)
        iconStickyToCorner: \(settings.isIconStickyToCorner)
        autoRotate: \(settings.isAutoRotateEnabled)
        waveformEnabled: \(settings.isWaveformEnabled)
        waveformState: \(String(describing: waveformState))
        panelFrame: \(panelController?.frameDescription ?? "not created")

        Network
        -------
        last request: not exposed
        status: not exposed
        latency: not exposed

        Errors
        ------
        last error: \(diagnosticError)
        artwork error: \(lastArtworkError ?? "None")
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

    var waveformStatusText: String {
        switch waveformState {
        case .disabled:
            return settings.isWaveformEnabled
                ? "Waiting for lyrics playback."
                : "Off"
        case .starting:
            return "Starting audio capture…"
        case .running:
            return "Capturing Apple Music audio."
        case .paused:
            return "Paused; the last waveform is retained."
        case .unavailable(.permissionDenied):
            return "Permission denied. Enable System Audio Recording for dynasic in System Settings, then turn waveform off and on to retry."
        case .unavailable(.musicUnavailable):
            return "Music.app unavailable."
        case .unavailable(.unsupportedFormat):
            return "The current Apple Music audio format is unsupported."
        case let .unavailable(.captureFailed(message)):
            return "Audio capture failed: \(message)"
        }
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

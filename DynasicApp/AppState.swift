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
    private var panelController: LyricsPanelController?

    var panelControllerForTesting: LyricsPanelController? { panelController }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
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

        let provider = LRCLIBProvider(httpClient: URLSessionHTTPClient())
        coordinator = LyricsCoordinator(
            provider: provider,
            cache: LyricsCache()
        )
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

    func refreshViewState() {
        Task { [weak self, coordinator] in
            let state = await coordinator.currentState()
            self?.viewState = state
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
        """
        Application
        -----------
        product: dynasic
        state: \(String(describing: viewState))
        lyricsVisible: \(isLyricsVisible)
        lyricsOffset: \(lyricsOffset)s
        lyricsFontSize: \(lyricsFontSize)
        lyricsOpacity: \(lyricsOpacity)
        lyricsAlignment: \(lyricsAlignment.rawValue)
        clickThrough: \(isClickThrough)
        alwaysOnTop: \(isAlwaysOnTop)
        """
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

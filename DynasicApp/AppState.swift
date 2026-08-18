import Combine
import LyricsCore

@MainActor
final class DynasicAppState: ObservableObject {
    @Published private(set) var viewState: LyricsViewState = .idle
    @Published var isLyricsVisible = false
    @Published var lyricsOffset = 0.0

    let coordinator: LyricsCoordinator

    init() {
        let provider = LRCLIBProvider(httpClient: URLSessionHTTPClient())
        coordinator = LyricsCoordinator(
            provider: provider,
            cache: LyricsCache()
        )
    }

    func showLyrics() {
        isLyricsVisible = true
    }

    func hideLyrics() {
        isLyricsVisible = false
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
        """
    }
}

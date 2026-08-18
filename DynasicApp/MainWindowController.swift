import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    init(state: DynasicAppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "dynasic"
        window.minSize = NSSize(width: 460, height: 280)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainWindowView(state: state))

        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) 尚未實作")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    var isVisible: Bool {
        window?.isVisible == true
    }
}

struct MainWindowView: View {
    @ObservedObject var state: DynasicAppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("dynasic")
                        .font(.title2.weight(.semibold))
                    Text("Floating synchronized lyrics")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text(state.trackTitle)
                    .font(.title3.weight(.medium))
                    .lineLimit(2)

                if !state.trackArtist.isEmpty {
                    Text(state.trackArtist)
                        .foregroundStyle(.secondary)
                }

                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(statusColor)
                    .padding(.top, 5)
            }

            Spacer()

            HStack(spacing: 10) {
                Button(state.isLyricsVisible ? "Hide Lyrics" : "Show Lyrics") {
                    if state.isLyricsVisible {
                        state.hideLyrics()
                    } else {
                        state.showLyrics()
                    }
                }
                .keyboardShortcut(.defaultAction)

                Button("Settings") {
                    openWindow(id: "settings")
                }

                Button("Diagnostics") {
                    state.refreshViewState()
                    openWindow(id: "diagnostics")
                }

                Spacer()
            }
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 280)
        .onAppear {
            state.refreshViewState()
        }
    }

    private var statusText: String {
        switch state.viewState {
        case .idle:
            return "Waiting for Apple Music"
        case .loading:
            return "Loading lyrics…"
        case .displaying:
            return "Lyrics ready"
        case .noLyrics:
            return "No synced lyrics found"
        case .musicUnavailable:
            return "Apple Music unavailable"
        case .nothingPlaying:
            return "Nothing playing"
        case .error:
            return "Lyrics provider error"
        }
    }

    private var statusColor: Color {
        switch state.viewState {
        case .displaying:
            return .green
        case .error, .musicUnavailable:
            return .red
        default:
            return .secondary
        }
    }
}

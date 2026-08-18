import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: DynasicAppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.trackTitle)
                .font(.headline)

            if !state.trackArtist.isEmpty {
                Text(state.trackArtist)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(state.isLyricsVisible ? "Hide Lyrics" : "Show Lyrics") {
                if state.isLyricsVisible {
                    state.hideLyrics()
                } else {
                    state.showLyrics()
                }
            }

            Menu("Lyrics Offset") {
                Button("-0.5 sec") { state.lyricsOffset = -0.5 }
                Button("0 sec") { state.lyricsOffset = 0 }
                Button("+0.5 sec") { state.lyricsOffset = 0.5 }
            }

            Button("Settings") {
                openWindow(id: "settings")
            }

            Button("Diagnostics") {
                state.refreshViewState()
                openWindow(id: "diagnostics")
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}

struct SettingsView: View {
    @ObservedObject var state: DynasicAppState

    var body: some View {
        Form {
            Section("Lyrics") {
                Slider(value: $state.lyricsFontSize, in: 12...48, step: 1) {
                    Text("Font Size")
                }
                Text("\(state.lyricsFontSize, specifier: "%.0f") pt")

                Slider(value: $state.lyricsOpacity, in: 0.2...1, step: 0.05) {
                    Text("Opacity")
                }
                Text("\(state.lyricsOpacity * 100, specifier: "%.0f")%")

                Picker("Alignment", selection: $state.lyricsAlignment) {
                    ForEach(LyricsPanelAlignment.allCases) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }

                Slider(value: $state.lyricsOffset, in: -5...5, step: 0.05) {
                    Text("Lyrics Offset")
                }
                Text("\(state.lyricsOffset, specifier: "%.2f") sec")
            }

            Section("Panel") {
                Toggle("Click-through", isOn: $state.isClickThrough)
                Toggle("Always on top", isOn: $state.isAlwaysOnTop)
                Toggle("Show previous line", isOn: $state.showsPreviousLine)
                Toggle("Show next line", isOn: $state.showsNextLine)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var state: DynasicAppState

    var body: some View {
        ScrollView {
            Text(state.diagnosticsText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(width: 480, height: 320)
    }
}

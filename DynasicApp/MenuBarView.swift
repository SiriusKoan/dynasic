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

            Button("Open dynasic") {
                state.showMainWindow()
            }

            Button(state.isLyricsVisible ? "Hide Lyrics" : "Show Lyrics") {
                if state.isLyricsVisible {
                    state.hideLyrics()
                } else {
                    state.showLyrics()
                }
            }

            Menu("Lyrics Offset") {
                Button("-0.5 sec") { state.settings.lyricsOffset = -0.5 }
                Button("0 sec") { state.settings.lyricsOffset = 0 }
                Button("+0.5 sec") { state.settings.lyricsOffset = 0.5 }
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
                Slider(value: $state.settings.lyricsFontSize, in: 12...48, step: 1) {
                    Text("Font Size")
                }
                Text("\(state.settings.lyricsFontSize, specifier: "%.0f") pt")

                Slider(value: $state.settings.lyricsOpacity, in: 0.2...1, step: 0.05) {
                    Text("Opacity")
                }
                Text("\(state.settings.lyricsOpacity * 100, specifier: "%.0f")%")

                Picker("Alignment", selection: $state.settings.lyricsAlignment) {
                    ForEach(LyricsPanelAlignment.allCases) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }

                Picker("Layout", selection: $state.settings.lyricsPanelLayout) {
                    ForEach(LyricsPanelLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }

                Slider(value: $state.settings.lyricsOffset, in: -5...5, step: 0.05) {
                    Text("Lyrics Offset")
                }
                Text("\(state.settings.lyricsOffset, specifier: "%.2f") sec")
            }

            Section("Panel") {
                Toggle("Click-through", isOn: $state.settings.isClickThrough)
                Toggle("Always on top", isOn: $state.settings.isAlwaysOnTop)
                Toggle("Sticky to corner", isOn: $state.settings.isStickyToCorner)
                Toggle("Auto Rotate", isOn: $state.settings.isAutoRotateEnabled)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var state: DynasicAppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(state.diagnosticsText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Copy Diagnostics") {
                    state.copyDiagnostics()
                }
            }
            .padding(10)
        }
        .frame(width: 480, height: 320)
    }
}

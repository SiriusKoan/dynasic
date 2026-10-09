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
                Button("-0.5 sec") { state.settings.lyricsOffset = -0.5 }
                Button("0 sec") { state.settings.lyricsOffset = 0 }
                Button("+0.5 sec") { state.settings.lyricsOffset = 0.5 }
            }

            Button("Settings") {
                DynasicAuxiliaryWindow.settings.open(using: openWindow)
            }

            Button("Diagnostics") {
                state.refreshViewState()
                DynasicAuxiliaryWindow.diagnostics.open(using: openWindow)
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
                Toggle(
                    "Sticky lyrics window to corners and edge centers",
                    isOn: $state.settings.isLyricsWindowStickyToEdges
                )
                Toggle("Sticky icon to corner", isOn: $state.settings.isIconStickyToCorner)
                Toggle("Auto Rotate", isOn: $state.settings.isAutoRotateEnabled)
            }

            Section("Waveform") {
                Toggle("Show Apple Music waveform", isOn: $state.settings.isWaveformEnabled)
                WaveformStatusView(
                    state: state,
                    presentation: state.waveformPresentation
                )
            }
        }
        .padding()
        .frame(width: 360)
    }
}

private struct WaveformStatusView: View {
    let state: DynasicAppState
    @ObservedObject var presentation: WaveformPresentation

    var body: some View {
        Text(state.waveformStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)
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

import AppKit
import Foundation
import SwiftUI
import LyricsCore

struct LyricsPanelView: View {
    @ObservedObject var state: DynasicAppState
    @ObservedObject var controller: LyricsPanelController

    var body: some View {
        Group {
            if controller.isCollapsed {
                Button {
                    controller.toggleCollapsed()
                } label: {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand lyrics")
            } else {
                regularLayout
                    .overlay(alignment: .topTrailing) {
                        Button {
                            controller.toggleCollapsed()
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.caption.weight(.semibold))
                                .padding(5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse lyrics")
                    }
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .opacity(state.settings.lyricsOpacity)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var regularLayout: some View {
        if state.settings.lyricsPanelLayout == .expanded {
            expandedLayout
        } else {
            lyricsOnlyLayout
        }
    }

    private var expandedLayout: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 16) {
                trackSummary

                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 160)

                lyricsContent
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)

            Divider()

            playbackControls

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var trackSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            artworkView
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(state.trackTitle)
                .font(.headline)
                .lineLimit(2)

            Text(state.trackArtist.isEmpty ? "—" : state.trackArtist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            playbackProgress
        }
        .frame(minWidth: 130, idealWidth: 160, maxWidth: 200, alignment: .leading)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork = state.trackArtwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .accessibilityLabel("Album artwork")
        } else {
            ZStack {
                Color.secondary.opacity(0.16)
                Image(systemName: "music.note")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Album artwork unavailable")
        }
    }

    @ViewBuilder
    private var playbackProgress: some View {
        if let duration = state.trackDuration, duration > 0 {
            ProgressView(value: clampedPlaybackPosition, total: duration)
                .progressViewStyle(.linear)

            HStack {
                Text(formattedTime(state.estimatedPlaybackPosition))
                Spacer()
                Text(formattedTime(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        } else {
            ProgressView(value: 0, total: 1)
                .progressViewStyle(.linear)
                .opacity(0.35)

            Text("— / —")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var clampedPlaybackPosition: TimeInterval {
        guard let duration = state.trackDuration, duration > 0 else { return 0 }
        return min(max(state.estimatedPlaybackPosition ?? 0, 0), duration)
    }

    private var playbackControls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 24) {
                Button {
                    _ = state.previousTrack()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .accessibilityLabel("Previous track")

                Button {
                    _ = state.togglePlayPause()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(state.isPlaying ? "Pause" : "Play")

                Button {
                    _ = state.nextTrack()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .accessibilityLabel("Next track")
            }
            .font(.title3)
            .buttonStyle(.plain)
            .disabled(!state.hasCurrentTrack)

            if let error = state.lastPlaybackControlError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var lyricsOnlyLayout: some View {
        lyricsContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var lyricsContent: some View {
        VStack(alignment: horizontalAlignment, spacing: 6) {
            if let lines = selectedLines {
                if state.settings.showsPreviousLine, let previous = lines.previous {
                    Text(previous.text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(lines.current)
                    .font(.system(size: state.settings.lyricsFontSize, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(textAlignment)

                if state.settings.showsNextLine, let next = lines.next {
                    Text(next.text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No lyrics")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch state.settings.lyricsAlignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private var textAlignment: TextAlignment {
        switch state.settings.lyricsAlignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private var selectedLines: (previous: LyricLine?, current: String, next: LyricLine?)? {
        guard case let .displaying(_, lyrics, currentIndex) = state.viewState,
              let currentIndex,
              lyrics.lines.indices.contains(currentIndex) else {
            return nil
        }

        return (
            currentIndex > 0 ? lyrics.lines[currentIndex - 1] : nil,
            lyrics.lines[currentIndex].text,
            currentIndex + 1 < lyrics.lines.count ? lyrics.lines[currentIndex + 1] : nil
        )
    }

    private func formattedTime(_ value: TimeInterval?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        let totalSeconds = Int(value.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

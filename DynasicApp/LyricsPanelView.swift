import AppKit
import Foundation
import SwiftUI
import LyricsCore

struct LyricsPanelView: View {
    @ObservedObject var state: DynasicAppState
    @ObservedObject var controller: LyricsPanelController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if controller.isCollapsed {
                GeometryReader { proxy in
                    ZStack {
                        Image("DynasicCollapsedIcon")
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(1.12)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Expand lyrics")
            } else {
                regularLayout
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 2) {
                            Button {
                                openWindow(id: "settings")
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.caption.weight(.semibold))
                                    .padding(5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Settings")

                            Button {
                                state.refreshViewState()
                                openWindow(id: "diagnostics")
                            } label: {
                                Image(systemName: "stethoscope")
                                    .font(.caption.weight(.semibold))
                                    .padding(5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Diagnostics")

                            Button {
                                controller.rotateContent()
                            } label: {
                                Image(systemName: "rotate.right")
                                    .font(.caption.weight(.semibold))
                                    .padding(5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rotate layout")

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
        switch state.settings.lyricsPanelLayout {
        case .expanded:
            expandedLayout
        case .lyricsOnly:
            lyricsOnlyLayout
        case .songInfoOnly:
            songInfoOnlyLayout
        }
    }

    private var expandedLayout: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            expandedContentLayout {
                trackSummary

                trackLyricsDivider

                lyricsContent
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.24), value: controller.contentOrientation)
    }

    private var expandedContentLayout: AnyLayout {
        switch controller.contentOrientation {
        case .horizontal:
            return AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        case .vertical:
            return AnyLayout(VStackLayout(alignment: .center, spacing: 12))
        }
    }

    @ViewBuilder
    private var trackLyricsDivider: some View {
        switch controller.contentOrientation {
        case .horizontal:
            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: 72)
        case .vertical:
            Divider()
        }
    }

    private var trackSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                artworkView
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.trackTitle)
                        .font(.headline)
                        .lineLimit(2)

                    Text(state.trackArtist.isEmpty ? "—" : state.trackArtist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if state.settings.isWaveformEnabled,
               let frame = state.waveformState.frame {
                WaveformView(frame: frame)
                    .frame(height: 28)
            }

            playbackProgress
        }
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 280, alignment: .leading)
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
            HStack(spacing: 8) {
                Text(formattedTime(state.estimatedPlaybackPosition))
                ProgressView(value: clampedPlaybackPosition, total: duration)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
                Text(formattedTime(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                Text("—")
                ProgressView(value: 0, total: 1)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
                    .opacity(0.35)
                Text("—")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var clampedPlaybackPosition: TimeInterval {
        guard let duration = state.trackDuration, duration > 0 else { return 0 }
        return min(max(state.estimatedPlaybackPosition ?? 0, 0), duration)
    }

    private var lyricsOnlyLayout: some View {
        VStack(spacing: 12) {
            lyricsContent
                .frame(maxWidth: .infinity, alignment: .center)

            if state.settings.isWaveformEnabled,
               let frame = state.waveformState.frame {
                WaveformView(frame: frame)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var songInfoOnlyLayout: some View {
        trackSummary
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var lyricsContent: some View {
        if let lines = selectedLines {
            lyricsStack(lines)
        } else {
            Text("No lyrics")
                .foregroundStyle(.secondary)
        }
    }

    private func lyricsStack(_ lines: LyricsLinePresentation) -> some View {
        VStack(alignment: horizontalAlignment, spacing: 6) {
            ForEach(lines.lines) { item in
                lyricText(item)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .clipped()
        .animation(.easeOut(duration: 0.24), value: lines.id)
    }

    @ViewBuilder
    private func lyricText(_ item: LyricsLinePresentation.VisibleLine) -> some View {
        if item.role == .current {
            Text(item.line.text)
                .font(.system(size: state.settings.lyricsFontSize, weight: .semibold))
                .lineLimit(nil)
                .multilineTextAlignment(textAlignment)
                .frame(maxWidth: .infinity, alignment: alignment)
        } else {
            Text(item.line.text)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .multilineTextAlignment(textAlignment)
                .frame(maxWidth: .infinity, alignment: alignment)
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

    private var alignment: Alignment {
        switch state.settings.lyricsAlignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private var selectedLines: LyricsLinePresentation? {
        LyricsLinePresentation(viewState: state.viewState)
    }

    private func formattedTime(_ value: TimeInterval?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        let totalSeconds = Int(value.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct WaveformView: View {
    let frame: WaveformFrame

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 2
            let count = CGFloat(WaveformSpectrumProcessor.columnCount)
            let barWidth = max(1, (proxy.size.width - spacing * (count - 1)) / count)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(frame.levels.prefix(WaveformSpectrumProcessor.columnCount).enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .frame(
                            width: barWidth,
                            height: max(2, proxy.size.height * CGFloat(min(max(level, 0), 1)))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .foregroundStyle(.primary.opacity(0.72))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Music frequency spectrum")
    }
}

struct LyricsLinePresentation: Equatable, Identifiable {
    struct ID: Equatable, Hashable {
        let track: TrackIdentity
        let currentIndex: Int
    }

    enum Role: Equatable {
        case previous
        case current
        case next
    }

    struct VisibleLine: Equatable, Identifiable {
        struct ID: Equatable, Hashable {
            let track: TrackIdentity
            let lineIndex: Int
        }

        let id: ID
        let line: LyricLine
        let role: Role
    }

    let id: ID
    let lines: [VisibleLine]

    init?(viewState: LyricsViewState) {
        guard case let .displaying(track, lyrics, currentIndex) = viewState,
              let currentIndex,
              lyrics.lines.indices.contains(currentIndex) else {
            return nil
        }

        let trackIdentity = TrackIdentity(metadata: track)
        id = ID(track: trackIdentity, currentIndex: currentIndex)
        let lowerBound = max(lyrics.lines.startIndex, currentIndex - 1)
        let upperBound = min(lyrics.lines.index(before: lyrics.lines.endIndex), currentIndex + 1)
        lines = (lowerBound...upperBound).map { index in
            let role: Role = if index < currentIndex {
                .previous
            } else if index > currentIndex {
                .next
            } else {
                .current
            }
            return VisibleLine(
                id: VisibleLine.ID(track: trackIdentity, lineIndex: index),
                line: lyrics.lines[index],
                role: role
            )
        }
    }
}

import SwiftUI
import LyricsCore

struct LyricsPanelView: View {
    @ObservedObject var state: DynasicAppState

    var body: some View {
        VStack(spacing: 6) {
            if let lines = selectedLines {
                if let previous = lines.previous {
                    Text(previous.text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(lines.current)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                if let next = lines.next {
                    Text(next.text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("No lyrics")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
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
}

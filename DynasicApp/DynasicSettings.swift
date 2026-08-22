import Foundation

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

enum LyricsPanelLayout: String, CaseIterable, Identifiable {
    case expanded
    case lyricsOnly = "lyrics-only"

    var id: Self { self }

    var title: String {
        switch self {
        case .expanded:
            return "Expanded"
        case .lyricsOnly:
            return "Lyrics Only"
        }
    }
}

struct DynasicSettings: Equatable {
    var lyricsOffset: Double
    var lyricsFontSize: Double
    var lyricsOpacity: Double
    var lyricsAlignment: LyricsPanelAlignment
    var lyricsPanelLayout: LyricsPanelLayout
    var isClickThrough: Bool
    var isAlwaysOnTop: Bool
    var isStickyToCorner: Bool
    var isAutoRotateEnabled: Bool
    var isWaveformEnabled: Bool

    static let defaults = DynasicSettings(
        lyricsOffset: 0,
        lyricsFontSize: 22,
        lyricsOpacity: 1,
        lyricsAlignment: .center,
        lyricsPanelLayout: .expanded,
        isClickThrough: false,
        isAlwaysOnTop: true,
        isStickyToCorner: false,
        isAutoRotateEnabled: true,
        isWaveformEnabled: false
    )
}

struct DynasicSettingsStore {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        userDefaults.register(defaults: [
            Key.lyricsOffset: DynasicSettings.defaults.lyricsOffset,
            Key.lyricsFontSize: DynasicSettings.defaults.lyricsFontSize,
            Key.lyricsOpacity: DynasicSettings.defaults.lyricsOpacity,
            Key.lyricsAlignment: DynasicSettings.defaults.lyricsAlignment.rawValue,
            Key.lyricsPanelLayout: DynasicSettings.defaults.lyricsPanelLayout.rawValue,
            Key.isClickThrough: DynasicSettings.defaults.isClickThrough,
            Key.isAlwaysOnTop: DynasicSettings.defaults.isAlwaysOnTop,
            Key.isStickyToCorner: DynasicSettings.defaults.isStickyToCorner,
            Key.isAutoRotateEnabled: DynasicSettings.defaults.isAutoRotateEnabled,
            Key.isWaveformEnabled: DynasicSettings.defaults.isWaveformEnabled
        ])
    }

    func load() -> DynasicSettings {
        DynasicSettings(
            lyricsOffset: userDefaults.double(forKey: Key.lyricsOffset),
            lyricsFontSize: userDefaults.double(forKey: Key.lyricsFontSize),
            lyricsOpacity: userDefaults.double(forKey: Key.lyricsOpacity),
            lyricsAlignment: LyricsPanelAlignment(
                rawValue: userDefaults.string(forKey: Key.lyricsAlignment) ?? ""
            ) ?? .center,
            lyricsPanelLayout: LyricsPanelLayout(
                rawValue: userDefaults.string(forKey: Key.lyricsPanelLayout) ?? ""
            ) ?? .expanded,
            isClickThrough: userDefaults.bool(forKey: Key.isClickThrough),
            isAlwaysOnTop: userDefaults.bool(forKey: Key.isAlwaysOnTop),
            isStickyToCorner: userDefaults.bool(forKey: Key.isStickyToCorner),
            isAutoRotateEnabled: userDefaults.bool(forKey: Key.isAutoRotateEnabled),
            isWaveformEnabled: userDefaults.bool(forKey: Key.isWaveformEnabled)
        )
    }

    func save(_ settings: DynasicSettings) {
        userDefaults.set(settings.lyricsOffset, forKey: Key.lyricsOffset)
        userDefaults.set(settings.lyricsFontSize, forKey: Key.lyricsFontSize)
        userDefaults.set(settings.lyricsOpacity, forKey: Key.lyricsOpacity)
        userDefaults.set(settings.lyricsAlignment.rawValue, forKey: Key.lyricsAlignment)
        userDefaults.set(settings.lyricsPanelLayout.rawValue, forKey: Key.lyricsPanelLayout)
        userDefaults.set(settings.isClickThrough, forKey: Key.isClickThrough)
        userDefaults.set(settings.isAlwaysOnTop, forKey: Key.isAlwaysOnTop)
        userDefaults.set(settings.isStickyToCorner, forKey: Key.isStickyToCorner)
        userDefaults.set(settings.isAutoRotateEnabled, forKey: Key.isAutoRotateEnabled)
        userDefaults.set(settings.isWaveformEnabled, forKey: Key.isWaveformEnabled)
    }

    private enum Key {
        static let lyricsOffset = "dynasic.settings.lyricsOffset"
        static let lyricsFontSize = "dynasic.settings.lyricsFontSize"
        static let lyricsOpacity = "dynasic.settings.lyricsOpacity"
        static let lyricsAlignment = "dynasic.settings.lyricsAlignment"
        static let lyricsPanelLayout = "dynasic.settings.lyricsPanelLayout"
        static let isClickThrough = "dynasic.settings.isClickThrough"
        static let isAlwaysOnTop = "dynasic.settings.isAlwaysOnTop"
        static let isStickyToCorner = "dynasic.settings.isStickyToCorner"
        static let isAutoRotateEnabled = "dynasic.settings.isAutoRotateEnabled"
        static let isWaveformEnabled = "dynasic.settings.isWaveformEnabled"
    }
}

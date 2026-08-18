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

struct DynasicSettings: Equatable {
    var lyricsOffset: Double
    var lyricsFontSize: Double
    var lyricsOpacity: Double
    var lyricsAlignment: LyricsPanelAlignment
    var isClickThrough: Bool
    var isAlwaysOnTop: Bool
    var showsPreviousLine: Bool
    var showsNextLine: Bool

    static let defaults = DynasicSettings(
        lyricsOffset: 0,
        lyricsFontSize: 22,
        lyricsOpacity: 1,
        lyricsAlignment: .center,
        isClickThrough: false,
        isAlwaysOnTop: true,
        showsPreviousLine: true,
        showsNextLine: true
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
            Key.isClickThrough: DynasicSettings.defaults.isClickThrough,
            Key.isAlwaysOnTop: DynasicSettings.defaults.isAlwaysOnTop,
            Key.showsPreviousLine: DynasicSettings.defaults.showsPreviousLine,
            Key.showsNextLine: DynasicSettings.defaults.showsNextLine
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
            isClickThrough: userDefaults.bool(forKey: Key.isClickThrough),
            isAlwaysOnTop: userDefaults.bool(forKey: Key.isAlwaysOnTop),
            showsPreviousLine: userDefaults.bool(forKey: Key.showsPreviousLine),
            showsNextLine: userDefaults.bool(forKey: Key.showsNextLine)
        )
    }

    func save(_ settings: DynasicSettings) {
        userDefaults.set(settings.lyricsOffset, forKey: Key.lyricsOffset)
        userDefaults.set(settings.lyricsFontSize, forKey: Key.lyricsFontSize)
        userDefaults.set(settings.lyricsOpacity, forKey: Key.lyricsOpacity)
        userDefaults.set(settings.lyricsAlignment.rawValue, forKey: Key.lyricsAlignment)
        userDefaults.set(settings.isClickThrough, forKey: Key.isClickThrough)
        userDefaults.set(settings.isAlwaysOnTop, forKey: Key.isAlwaysOnTop)
        userDefaults.set(settings.showsPreviousLine, forKey: Key.showsPreviousLine)
        userDefaults.set(settings.showsNextLine, forKey: Key.showsNextLine)
    }

    private enum Key {
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

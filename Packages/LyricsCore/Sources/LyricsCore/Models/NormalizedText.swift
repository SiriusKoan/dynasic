import Foundation

enum NormalizedText {
    static func value(_ source: String) -> String {
        source
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    static func optional(_ source: String?) -> String? {
        guard let source else { return nil }
        let normalized = value(source)
        return normalized.isEmpty ? nil : normalized
    }
}

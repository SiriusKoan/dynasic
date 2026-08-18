import Foundation

enum AppleMusicTTMLParser {
    static func parse(_ source: String) -> Lyrics? {
        guard let data = source.data(using: .utf8) else { return nil }

        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false

        guard parser.parse(), !delegate.lines.isEmpty else { return nil }
        return Lyrics(lines: delegate.lines.sorted { $0.timestamp < $1.timestamp })
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var lines: [LyricLine] = []

        private var depth = 0
        private var bodyDepth: Int?
        private var currentLine: LineBuilder?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            depth += 1
            let name = localName(elementName, qualifiedName: qName)

            if name == "body" {
                bodyDepth = depth
                return
            }
            guard bodyDepth != nil else { return }

            switch name {
            case "p":
                currentLine = LineBuilder(timestamp: time(attributeDict["begin"]))
            case "span":
                if currentLine?.timestamp == nil,
                   let timestamp = time(attributeDict["begin"]) {
                    currentLine?.timestamp = timestamp
                }
            case "br":
                currentLine?.text.append("\n")
            default:
                break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = localName(elementName, qualifiedName: qName)

            if name == "p", let line = currentLine {
                let text = normalizedWhitespace(line.text)
                if let timestamp = line.timestamp, !text.isEmpty {
                    lines.append(LyricLine(timestamp: timestamp, text: text))
                }
                currentLine = nil
            } else if name == "body", bodyDepth == depth {
                bodyDepth = nil
            }

            depth -= 1
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentLine?.text.append(string)
        }

        private func localName(_ elementName: String, qualifiedName: String?) -> String {
            let value = qualifiedName ?? elementName
            return value.split(separator: ":").last.map(String.init) ?? value
        }

        private func time(_ raw: String?) -> TimeInterval? {
            guard let raw else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            if value.hasSuffix("ms"),
               let milliseconds = Double(value.dropLast(2)) {
                return milliseconds / 1000
            }
            if value.hasSuffix("s"),
               let seconds = Double(value.dropLast()) {
                return seconds
            }

            let parts = value.split(separator: ":")
            let numbers = parts.compactMap { Double($0) }
            guard !parts.isEmpty, parts.count <= 3,
                  numbers.count == parts.count else {
                return nil
            }

            return numbers.reversed().enumerated().reduce(0) { result, item in
                result + item.element * pow(60, Double(item.offset))
            }
        }

        private func normalizedWhitespace(_ text: String) -> String {
            var result = ""
            var previousWasWhitespace = false

            for character in text {
                if character.isWhitespace {
                    if !previousWasWhitespace { result.append(" ") }
                    previousWasWhitespace = true
                } else {
                    result.append(character)
                    previousWasWhitespace = false
                }
            }

            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private struct LineBuilder {
            var timestamp: TimeInterval?
            var text = ""
        }
    }
}

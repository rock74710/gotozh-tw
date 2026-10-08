import Foundation

public struct DictionaryEntry: Codable, Equatable, Sendable {
    public let from: String
    public let to: String
    public let note: String
    public let tip: String
    public let example: String
    public let contextual: Bool

    public init(from: String, to: String, note: String, tip: String, example: String, contextual: Bool = false) {
        self.from = from
        self.to = to
        self.note = note
        self.tip = tip
        self.example = example
        self.contextual = contextual
    }
}

public enum BuiltInDictionary {
    public static let entries: [DictionaryEntry] = {
        guard let url = Bundle.module.url(forResource: "manual-dictionary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
        else {
            fatalError("The bundled manual dictionary is missing or invalid.")
        }
        return entries
    }()
}

public struct Occurrence: Equatable, Identifiable, Sendable {
    public var id: Int { startUTF16 }
    public let startUTF16: Int
    public let endUTF16: Int
    public let from: String
    public let to: String
    public let contextual: Bool
    public let kind: SuggestionKind
    public var applied: Bool
}

public struct ScanResult: Equatable, Sendable {
    public let source: String
    public var occurrences: [Occurrence]
    public let openCCError: String?
}

public enum SuggestionKind: String, Equatable, Sendable {
    case manual
    case openCC
}

public struct Converter: Sendable {
    public let dictionary: [DictionaryEntry]
    private let patterns: [Pattern]
    private let openCC: OpenCCBackend?
    private let openCCInitializationError: String?

    private struct Pattern: Sendable {
        let entry: DictionaryEntry
        let units: [UInt16]
        let order: Int
    }

    public init(dictionary: [DictionaryEntry] = BuiltInDictionary.entries, usesOpenCC: Bool = true) {
        self.dictionary = dictionary
        if usesOpenCC {
            switch OpenCCBackend.loadResult {
            case .success(let backend):
                openCC = backend
                openCCInitializationError = nil
            case .failure(let error):
                openCC = nil
                openCCInitializationError = error.localizedDescription
            }
        } else {
            openCC = nil
            openCCInitializationError = nil
        }
        patterns = dictionary.enumerated()
            .map { index, entry in
                Pattern(entry: entry, units: Array(entry.from.utf16), order: index)
            }
            .filter { !$0.units.isEmpty }
            .sorted { left, right in
                left.units.count == right.units.count
                    ? left.order < right.order
                    : left.units.count > right.units.count
            }
    }

    public func scan(_ text: String) -> ScanResult {
        let units = Array(text.utf16)
        var occurrences: [Occurrence] = []
        var cursor = 0

        while cursor < units.count {
            let matched = patterns.first { pattern in
                let end = cursor + pattern.units.count
                guard end <= units.count else { return false }
                return units[cursor..<end].elementsEqual(pattern.units)
            }

            if let matched {
                let end = cursor + matched.units.count
                occurrences.append(Occurrence(
                    startUTF16: cursor,
                    endUTF16: end,
                    from: matched.entry.from,
                    to: matched.entry.to,
                    contextual: matched.entry.contextual,
                    kind: .manual,
                    applied: false
                ))
                cursor = end
            } else {
                cursor += 1
            }
        }

        var openCCError = openCCInitializationError
        if let openCC {
            do {
                let manualOccurrences = occurrences
                for suggestion in try openCC.suggestions(in: text) {
                    let overlapsManualSuggestion = manualOccurrences.contains { manual in
                        suggestion.startUTF16 < manual.endUTF16 && manual.startUTF16 < suggestion.endUTF16
                    }
                    guard !overlapsManualSuggestion else { continue }
                    occurrences.append(Occurrence(
                        startUTF16: suggestion.startUTF16,
                        endUTF16: suggestion.endUTF16,
                        from: suggestion.from,
                        to: suggestion.to,
                        contextual: false,
                        kind: .openCC,
                        applied: false
                    ))
                }
            } catch {
                openCCError = error.localizedDescription
            }
        }

        occurrences.sort { $0.startUTF16 < $1.startUTF16 }
        return ScanResult(source: text, occurrences: occurrences, openCCError: openCCError)
    }

    public func toggleOccurrence(atUTF16Offset offset: Int, in result: ScanResult) -> ScanResult {
        var updated = result
        guard let index = updated.occurrences.firstIndex(where: { $0.startUTF16 == offset }) else {
            return updated
        }
        updated.occurrences[index].applied.toggle()
        return updated
    }

    public func replaceAll(in result: ScanResult) -> ScanResult {
        var updated = result
        for index in updated.occurrences.indices where !updated.occurrences[index].contextual {
            updated.occurrences[index].applied = true
        }
        return updated
    }

    public func output(for result: ScanResult) -> String {
        guard result.occurrences.contains(where: \.applied) else { return result.source }

        let sourceUnits = Array(result.source.utf16)
        var transformed: [UInt16] = []
        var cursor = 0
        for occurrence in result.occurrences {
            guard occurrence.startUTF16 >= cursor,
                  occurrence.endUTF16 <= sourceUnits.count else { continue }
            transformed.append(contentsOf: sourceUnits[cursor..<occurrence.startUTF16])
            if occurrence.applied {
                transformed.append(contentsOf: occurrence.to.utf16)
            } else {
                transformed.append(contentsOf: sourceUnits[occurrence.startUTF16..<occurrence.endUTF16])
            }
            cursor = occurrence.endUTF16
        }
        transformed.append(contentsOf: sourceUnits[cursor...])
        return String(decoding: transformed, as: UTF16.self)
    }
}

public struct DocumentSession: Sendable {
    private let converter: Converter
    public private(set) var sourceText: String
    public private(set) var result: ScanResult?

    public init(converter: Converter = Converter(), sourceText: String = "") {
        self.converter = converter
        self.sourceText = sourceText
        self.result = nil
    }

    public mutating func setSourceText(_ text: String) {
        sourceText = text
        result = nil
    }

    public mutating func scan() {
        result = converter.scan(sourceText)
    }

    public mutating func toggleOccurrence(atUTF16Offset offset: Int) {
        guard let current = result else { return }
        result = converter.toggleOccurrence(atUTF16Offset: offset, in: current)
    }

    public mutating func replaceAll() {
        guard let current = result else { return }
        result = converter.replaceAll(in: current)
    }

    public var output: String? {
        result.map(converter.output(for:))
    }
}

public enum UTF8Text {
    public static func decode(_ data: Data) throws -> String {
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw UTF8TextError()
        }
        return decoded
    }
}

public struct UTF8TextError: Error, LocalizedError, Sendable {
    public var errorDescription: String? { "檔案不是有效的 UTF-8 文字。" }
}

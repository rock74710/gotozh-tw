import Foundation
import OpenCCNative

struct OpenCCSuggestion: Equatable, Sendable {
    let startUTF16: Int
    let endUTF16: Int
    let from: String
    let to: String
}

final class OpenCCBackend: @unchecked Sendable {
    private struct Inspection: Decodable {
        struct Segment: Decodable {
            let from: String
            let to: String
        }

        let normalizedInput: String
        let segments: [Segment]
    }

    static let loadResult: Result<OpenCCBackend, OpenCCBackendError> = {
        do {
            return .success(try OpenCCBackend())
        } catch {
            return .failure(error as? OpenCCBackendError ?? .loadFailed(error.localizedDescription))
        }
    }()

    private let handle: OpaquePointer

    private init() throws {
        guard let resourceURL = Bundle.module.resourceURL?.appendingPathComponent("OpenCC", isDirectory: true) else {
            throw OpenCCBackendError.missingResources
        }
        let configURL = resourceURL.appendingPathComponent("config/s2twp.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw OpenCCBackendError.missingResources
        }
        guard let converter = gotozh_opencc_create(configURL.path, resourceURL.path) else {
            throw OpenCCBackendError.loadFailed(openCCLastError())
        }
        handle = converter
    }

    deinit {
        gotozh_opencc_destroy(handle)
    }

    func suggestions(in text: String) throws -> [OpenCCSuggestion] {
        guard !text.isEmpty else { return [] }

        let input = Data(text.utf8)
        var outputLength = 0
        let output = input.withUnsafeBytes { bytes -> UnsafeMutablePointer<CChar>? in
            guard let baseAddress = bytes.bindMemory(to: CChar.self).baseAddress else { return nil }
            return gotozh_opencc_inspect(handle, baseAddress, input.count, &outputLength)
        }
        guard let output else { throw OpenCCBackendError.inspectFailed(openCCLastError()) }
        defer { gotozh_opencc_free(output) }

        let jsonData = Data(bytes: UnsafeRawPointer(output), count: outputLength)
        let inspection: Inspection
        do {
            inspection = try JSONDecoder().decode(Inspection.self, from: jsonData)
        } catch {
            throw OpenCCBackendError.invalidInspection(error.localizedDescription)
        }
        let joinedSegments = inspection.segments.map({ $0.from }).joined()
        guard joinedSegments == inspection.normalizedInput else {
            throw OpenCCBackendError.invalidInspection("OpenCC inspection segments do not match its normalized input.")
        }

        let sourceScalars = Array(text.unicodeScalars)
        let normalizedScalars = Array(inspection.normalizedInput.unicodeScalars)
        guard sourceScalars.count == normalizedScalars.count else {
            throw OpenCCBackendError.invalidInspection("OpenCC normalization changed the number of Unicode scalars, so source positions cannot be mapped safely.")
        }

        var utf16Offsets = [Int](repeating: 0, count: sourceScalars.count + 1)
        for (index, scalar) in sourceScalars.enumerated() {
            utf16Offsets[index + 1] = utf16Offsets[index] + (scalar.value > 0xFFFF ? 2 : 1)
        }

        var scalarCursor = 0
        var suggestions: [OpenCCSuggestion] = []
        for segment in inspection.segments {
            let scalarEnd = scalarCursor + segment.from.unicodeScalars.count
            guard scalarEnd <= sourceScalars.count else {
                throw OpenCCBackendError.invalidInspection("OpenCC inspection segment exceeds the source text.")
            }
            let originalScalars = Array(sourceScalars[scalarCursor..<scalarEnd])
            let convertedScalars = Array(segment.to.unicodeScalars)
            for hunk in changedHunks(from: originalScalars, to: convertedScalars) {
                let sourceStart = scalarCursor + hunk.source.lowerBound
                let sourceEnd = scalarCursor + hunk.source.upperBound
                let from = String(String.UnicodeScalarView(sourceScalars[sourceStart..<sourceEnd]))
                let to = String(String.UnicodeScalarView(convertedScalars[hunk.target]))
                suggestions.append(OpenCCSuggestion(
                    startUTF16: utf16Offsets[sourceStart],
                    endUTF16: utf16Offsets[sourceEnd],
                    from: from,
                    to: to
                ))
            }
            scalarCursor = scalarEnd
        }
        guard scalarCursor == sourceScalars.count else {
            throw OpenCCBackendError.invalidInspection("OpenCC inspection did not cover the full source text.")
        }
        return suggestions
    }

}

private struct ChangedHunk {
    let source: Range<Int>
    let target: Range<Int>
}

/// Find the changed runs in one OpenCC segment. CollectionDifference uses scalar
/// sequences here, keeping both the work and the resulting spans local to the
/// upstream segment rather than diffing the entire document.
private func changedHunks(from source: [Unicode.Scalar], to target: [Unicode.Scalar]) -> [ChangedHunk] {
    let difference = target.difference(from: source)
    var removals = Set<Int>()
    var insertions = Set<Int>()
    for change in difference {
        switch change {
        case .remove(let offset, _, _):
            removals.insert(offset)
        case .insert(let offset, _, _):
            insertions.insert(offset)
        }
    }

    var hunks: [ChangedHunk] = []
    var sourceCursor = 0
    var targetCursor = 0
    while sourceCursor < source.count || targetCursor < target.count {
        if !removals.contains(sourceCursor) && !insertions.contains(targetCursor) {
            sourceCursor += 1
            targetCursor += 1
            continue
        }

        let sourceStart = sourceCursor
        let targetStart = targetCursor
        var madeProgress: Bool
        repeat {
            madeProgress = false
            if removals.remove(sourceCursor) != nil {
                sourceCursor += 1
                madeProgress = true
            }
            if insertions.remove(targetCursor) != nil {
                targetCursor += 1
                madeProgress = true
            }
        } while madeProgress

        hunks.append(ChangedHunk(
            source: sourceStart..<sourceCursor,
            target: targetStart..<targetCursor
        ))
    }
    guard let firstHunk = hunks.first else { return [] }
    var merged = [firstHunk]
    for hunk in hunks.dropFirst() {
        let previous = merged[merged.count - 1]
        let sourceGap = previous.source.upperBound..<hunk.source.lowerBound
        let targetGap = previous.target.upperBound..<hunk.target.lowerBound
        let joinsOneCJKScalar = sourceGap.count == 1
            && targetGap.count == 1
            && source[sourceGap.lowerBound] == target[targetGap.lowerBound]
            && isCJK(source[sourceGap.lowerBound])
        if joinsOneCJKScalar {
            merged[merged.count - 1] = ChangedHunk(
                source: previous.source.lowerBound..<hunk.source.upperBound,
                target: previous.target.lowerBound..<hunk.target.upperBound
            )
        } else {
            merged.append(hunk)
        }
    }
    var splitRepeated: [ChangedHunk] = []
    for hunk in merged {
        let sourcePart = Array(source[hunk.source])
        let targetPart = Array(target[hunk.target])
        guard let sourcePeriod = repeatedPeriodLength(sourcePart),
              let targetPeriod = repeatedPeriodLength(targetPart) else {
            splitRepeated.append(hunk)
            continue
        }
        let repetitionCount = sourcePart.count / sourcePeriod
        guard repetitionCount >= 2,
              repetitionCount == targetPart.count / targetPeriod else {
            splitRepeated.append(hunk)
            continue
        }
        for repetition in 0..<repetitionCount {
            let sourceStart = hunk.source.lowerBound + repetition * sourcePeriod
            let targetStart = hunk.target.lowerBound + repetition * targetPeriod
            splitRepeated.append(ChangedHunk(
                source: sourceStart..<(sourceStart + sourcePeriod),
                target: targetStart..<(targetStart + targetPeriod)
            ))
        }
    }
    return splitRepeated
}

private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    let value = scalar.value
    return (0x3400...0x4DBF).contains(value)
        || (0x4E00...0x9FFF).contains(value)
        || (0xF900...0xFAFF).contains(value)
        || (0x20000...0x323AF).contains(value)
}

private func repeatedPeriodLength(_ scalars: [Unicode.Scalar]) -> Int? {
    guard scalars.count > 1 else { return nil }
    var prefixLengths = [Int](repeating: 0, count: scalars.count)
    for index in 1..<scalars.count {
        var matchedLength = prefixLengths[index - 1]
        while matchedLength > 0 && scalars[index] != scalars[matchedLength] {
            matchedLength = prefixLengths[matchedLength - 1]
        }
        if scalars[index] == scalars[matchedLength] {
            matchedLength += 1
        }
        prefixLengths[index] = matchedLength
    }
    let period = scalars.count - prefixLengths[scalars.count - 1]
    return period < scalars.count && scalars.count.isMultiple(of: period) ? period : nil
}

private func openCCLastError() -> String {
    guard let message = gotozh_opencc_last_error() else { return "unknown error" }
    return String(cString: message)
}

enum OpenCCBackendError: Error, LocalizedError, Sendable {
    case missingResources
    case loadFailed(String)
    case inspectFailed(String)
    case invalidInspection(String)

    var errorDescription: String? {
        switch self {
        case .missingResources:
            "OpenCC configuration or dictionaries are missing from the app bundle."
        case .loadFailed(let message):
            message
        case .inspectFailed(let message):
            "OpenCC could not scan the text: \(message)"
        case .invalidInspection(let message):
            message
        }
    }
}

#if canImport(Darwin)
import Darwin
#elseif canImport(ucrt)
import ucrt
#endif
import Foundation
import GotozhCore

private struct JSONOccurrence: Encodable {
    let startUTF16: Int
    let endUTF16: Int
    let from: String
    let to: String
    let contextual: Bool
    let kind: String
}

private struct JSONScanResult: Encodable {
    let sourceUTF16Length: Int
    let occurrences: [JSONOccurrence]
    let openCCError: String?

    init(source: String, occurrences: [Occurrence], openCCError: String?) {
        sourceUTF16Length = source.utf16.count
        self.openCCError = openCCError
        self.occurrences = occurrences.map {
            JSONOccurrence(
                startUTF16: $0.startUTF16,
                endUTF16: $0.endUTF16,
                from: $0.from,
                to: $0.to,
                contextual: $0.contextual,
                kind: $0.kind.rawValue
            )
        }
    }
}

private enum CLIError: Error, LocalizedError {
    case usage(String)
    case conversion(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): message
        case .conversion(let message): message
        }
    }
}

@main
struct GotozhCLI {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch CLIError.usage(let message) {
            write(message + "\n", to: .standardError)
            exit(2)
        } catch {
            write("錯誤：\(error.localizedDescription)\n", to: .standardError)
            exit(1)
        }
    }

    private static func run(arguments: [String]) throws {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] {
            write(helpText, to: .standardOutput)
            return
        }

        guard let command = arguments.first, command == "scan" || command == "convert" else {
            throw CLIError.usage("未知命令。\n\n\(helpText)")
        }
        guard arguments.count <= 2 else {
            throw CLIError.usage("每次只能指定一個輸入檔。\n\n\(helpText)")
        }

        let filePath = arguments.count == 2 ? arguments[1] : nil
        let source = try readInput(from: filePath)
        let converter = Converter()
        let scanned = converter.scan(source)

        if command == "scan" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = try encoder.encode(JSONScanResult(
                source: source,
                occurrences: scanned.occurrences,
                openCCError: scanned.openCCError
            ))
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data([0x0A]))
        } else {
            guard scanned.openCCError == nil else {
                throw CLIError.conversion("OpenCC 掃描失敗：\(scanned.openCCError ?? "unknown error")")
            }
            let result = converter.replaceAll(in: scanned)
            FileHandle.standardOutput.write(Data(converter.output(for: result).utf8))
        }
    }

    private static func readInput(from filePath: String?) throws -> String {
        let data: Data
        if let filePath, filePath != "-" {
            data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        } else {
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        return try UTF8Text.decode(data)
    }

    private static func write(_ text: String, to handle: FileHandle) {
        handle.write(Data(text.utf8))
    }

    private static let helpText = """
    gotozh — 台灣用語掃描與轉換

    用法：
      gotozh --help
      gotozh scan [檔案.txt|-]
      gotozh convert [檔案.txt|-]

    不指定檔案或使用 - 時，從標準輸入讀取 UTF-8 文字。
    scan 輸出 JSON；位置以 UTF-16 半開區間表示。
    convert 套用 OpenCC 與一般內建建議，需看情境的內建詞會保留原文。
    結果一律輸出至標準輸出，不會改寫輸入檔。
    """
}

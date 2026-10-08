import AppKit
import GotozhCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class AppModel: ObservableObject {
    @Published private(set) var sourceText = ""
    @Published private(set) var result: ScanResult?
    @Published var errorMessage: String?

    private var session = DocumentSession()
    private let entriesBySource = Dictionary(uniqueKeysWithValues: BuiltInDictionary.entries.map { ($0.from, $0) })

    var outputText: String? { session.output }
    var entries: [DictionaryEntry] { BuiltInDictionary.entries }

    func editSource(_ text: String) {
        guard text != sourceText else { return }
        sourceText = text
        session.setSourceText(text)
        result = nil
    }

    func scan() {
        session.scan()
        result = session.result
    }

    func toggle(_ occurrence: Occurrence) {
        session.toggleOccurrence(atUTF16Offset: occurrence.startUTF16)
        result = session.result
    }

    func replaceAll() {
        session.replaceAll()
        result = session.result
    }

    func entry(for occurrence: Occurrence) -> DictionaryEntry? {
        guard occurrence.kind == .manual else { return nil }
        return entriesBySource[occurrence.from]
    }

    func context(for occurrence: Occurrence) -> String {
        let units = Array(sourceText.utf16)
        let radius = 14
        var start = max(0, occurrence.startUTF16 - radius)
        var end = min(units.count, occurrence.endUTF16 + radius)

        if start > 0, start < units.count,
           isLowSurrogate(units[start]), isHighSurrogate(units[start - 1]) {
            start -= 1
        }
        if end > 0, end < units.count,
           isHighSurrogate(units[end - 1]), isLowSurrogate(units[end]) {
            end += 1
        }

        let before = String(decoding: units[start..<occurrence.startUTF16], as: UTF16.self)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let after = String(decoding: units[occurrence.endUTF16..<end], as: UTF16.self)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return "\(start > 0 ? "…" : "")\(before)「\(occurrence.from)」\(after)\(end < units.count ? "…" : "")"
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.title = "開啟 UTF-8 文字檔"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            editSource(try UTF8Text.decode(data))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveFile() {
        guard let outputText else {
            errorMessage = "請先掃描文字，再儲存轉換結果。"
            return
        }

        let panel = NSSavePanel()
        panel.title = "儲存 UTF-8 文字檔"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "轉換結果.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Data(outputText.utf8).write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyResult() {
        guard let outputText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(outputText, forType: .string) else {
            errorMessage = "無法複製轉換結果。"
            return
        }
    }

    private func isHighSurrogate(_ unit: UInt16) -> Bool { (0xD800...0xDBFF).contains(unit) }
    private func isLowSurrogate(_ unit: UInt16) -> Bool { (0xDC00...0xDFFF).contains(unit) }
}

@main
struct GotozhMacApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .frame(minWidth: 900, minHeight: 680)
                .alert(
                    "檔案操作失敗",
                    isPresented: Binding(
                        get: { model.errorMessage != nil },
                        set: { if !$0 { model.errorMessage = nil } }
                    )
                ) {
                    Button("好", role: .cancel) { model.errorMessage = nil }
                } message: {
                    Text(model.errorMessage ?? "")
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("開啟文字檔…") { model.openFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("儲存轉換結果…") { model.saveFile() }
                    .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("開始掃描") { model.scan() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("全部替換一般用語") { model.replaceAll() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("複製轉換結果") { model.copyResult() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}

private struct MainView: View {
    @ObservedObject var model: AppModel

    private var sourceBinding: Binding<String> {
        Binding(get: { model.sourceText }, set: { model.editSource($0) })
    }

    private var appliedCount: Int { model.result?.occurrences.filter(\.applied).count ?? 0 }
    private var occurrenceCount: Int { model.result?.occurrences.count ?? 0 }
    private var replaceAllAvailable: Bool {
        guard let occurrences = model.result?.occurrences else { return false }
        return occurrences.contains { !$0.applied && !$0.contextual }
    }

    var body: some View {
        VStack(spacing: 12) {
            controls
            HSplitView {
                textPane(title: "原文", subtitle: "\(model.sourceText.count) 字") {
                    TextEditor(text: sourceBinding)
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                }
                .frame(minWidth: 300)
                textPane(title: "轉換結果", subtitle: resultSummary) {
                    ScrollView {
                        Text(model.outputText ?? "掃描後會在這裡顯示結果。")
                            .font(.system(size: 14, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                    }
                }
                .frame(minWidth: 300)
            }
            .frame(maxHeight: .infinity)
            suggestions
        }
        .padding(16)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: model.openFile) {
                Label("開啟文字檔…", systemImage: "doc")
            }
            Button(action: model.scan) {
                Label("開始掃描", systemImage: "magnifyingglass")
            }
            .keyboardShortcut(.return, modifiers: .command)
            Button(action: model.replaceAll) {
                Label("全部替換一般用語", systemImage: "arrow.left.arrow.right")
            }
            .disabled(!replaceAllAvailable)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Spacer()
            Button(action: model.copyResult) {
                Label("複製結果", systemImage: "doc.on.doc")
            }
            .disabled(model.outputText == nil)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Button(action: model.saveFile) {
                Label("儲存結果…", systemImage: "square.and.arrow.down")
            }
            .disabled(model.outputText == nil)
        }
    }

    private func textPane<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("逐處建議").font(.headline)
                Text("內建 \(BuiltInDictionary.entries.count) 組詞＋OpenCC 臺灣正體與慣用詞建議・情境詞會略過全部替換")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.result != nil {
                    Text("已替換 \(appliedCount) / \(occurrenceCount) 處")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let error = model.result?.openCCError {
                Text("OpenCC 掃描失敗；目前只顯示內建詞庫建議：\(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let result = model.result, !result.occurrences.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(result.occurrences) { occurrence in
                            SuggestionRow(
                                occurrence: occurrence,
                                entry: model.entry(for: occurrence),
                                context: model.context(for: occurrence),
                                toggle: { model.toggle(occurrence) }
                            )
                            Divider()
                        }
                    }
                }
                .frame(height: 205)
            } else {
                Text(model.result == nil
                     ? "輸入或開啟文字後，按「開始掃描」查看建議。"
                     : "沒有找到 OpenCC 或內建詞庫建議。範圍限於 OpenCC 臺灣轉換與 \(BuiltInDictionary.entries.count) 組內建詞，請依語意自行確認。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var resultSummary: String {
        guard model.result != nil else { return "尚未掃描" }
        return "已替換 \(appliedCount) / \(occurrenceCount) 處"
    }
}

private struct SuggestionRow: View {
    let occurrence: Occurrence
    let entry: DictionaryEntry?
    let context: String
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let entry {
                    HStack(spacing: 6) {
                        Text(entry.from).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption)
                        Text(entry.to).fontWeight(.semibold)
                        if entry.contextual {
                            Text("需看情境")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(context).font(.caption).foregroundStyle(.secondary)
                    Text(entry.note).font(.caption2).foregroundStyle(.secondary)
                    Text(entry.tip).font(.callout)
                    Text("例：\(entry.example)").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Text(occurrence.from).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption)
                        Text(occurrence.to).fontWeight(.semibold)
                        Text("OpenCC")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(context).font(.caption).foregroundStyle(.secondary)
                    Text("臺灣正體與慣用詞建議；請依上下文確認。")
                        .font(.callout)
                }
            }
            Spacer(minLength: 8)
            Button(occurrence.applied ? "還原" : "替換", action: toggle)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

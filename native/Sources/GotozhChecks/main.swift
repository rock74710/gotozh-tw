import Foundation
import GotozhCore

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

@main
struct GotozhChecks {
    static func main() {
        do {
            try runChecks()
            print("全部原生核心驗收通過。")
        } catch {
            fputs("驗收失敗：\(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func runChecks() throws {
        let dictionary = BuiltInDictionary.entries
        let expected: [(String, String, Bool)] = [
            ("文件夾", "資料夾", false), ("服務器", "伺服器", false),
            ("出租車", "計程車", false), ("代碼", "程式碼", true),
            ("默認", "預設", false), ("視頻", "影片", false),
            ("軟件", "軟體", false), ("硬盤", "硬碟", false),
            ("網絡", "網路", false), ("信息", "資訊", true),
            ("用戶", "使用者", true), ("屏幕", "螢幕", false),
            ("支持", "支援", true), ("數據", "資料", true),
            ("短信", "簡訊", false), ("聯繫", "聯絡", false)
        ]
        let screenEntries: [(String, String, Bool)] = [
            ("全屏", "全螢幕", false), ("外屏", "外螢幕", false),
            ("內屏", "內螢幕", false), ("内屏", "內螢幕", false),
            ("摺疊屏", "摺疊螢幕", false), ("折疊屏", "摺疊螢幕", false),
            ("折叠屏", "摺疊螢幕", false),
            ("默认", "預設", false), ("二维码", "QR Code", false), ("二維碼", "QR Code", false),
            ("性价比", "C/P 值", false), ("性價比", "C/P 值", false),
            ("質量", "品質", true), ("质量", "品質", true)
        ]
        try check(dictionary.count == expected.count + screenEntries.count, "內建詞庫應保留原有 16 組，並新增 7 組螢幕詞與 7 組網路文章詞。")
        try check(
            zip(dictionary.prefix(expected.count), expected).allSatisfy { actual, wanted in
                actual.from == wanted.0 && actual.to == wanted.1 && actual.contextual == wanted.2
            },
            "內建詞庫與 public/app.js 的 16 組詞或情境標記不一致。"
        )
        try check(
            zip(dictionary.suffix(screenEntries.count), screenEntries).allSatisfy { actual, wanted in
                actual.from == wanted.0 && actual.to == wanted.1 && actual.contextual == wanted.2
            },
            "新增的螢幕詞、網路文章詞或情境標記不正確。"
        )
        try check(dictionary.allSatisfy { !$0.note.isEmpty && !$0.tip.isEmpty && !$0.example.isEmpty }, "每組詞都要保留 note、tip、example。")

        try checkManualScreenVocabulary()
        try checkLongestOverlapAndUTF16Offsets()
        try checkIndependentToggleAndUndo()
        try checkContextualReplaceAll()
        try checkOpenCCSuggestionsAndOffsets()
        try checkOpenCCPhraseCoverage()
        try checkOpenCCExceptions()
        try checkQualityIsContextual()
        try checkContextualEntriesAreProtectedFromOpenCC()
        try checkContextualOverlapKeepsOtherOpenCCSuggestions()
        try checkSourceEditResetsState()
        try checkUTF8Decoding()
    }

    private static func checkManualScreenVocabulary() throws {
        let converter = Converter()
        let terms: [(String, String)] = [
            ("全屏", "全螢幕"), ("外屏", "外螢幕"),
            ("內屏", "內螢幕"), ("内屏", "內螢幕"),
            ("摺疊屏", "摺疊螢幕"), ("折疊屏", "摺疊螢幕"),
            ("折叠屏", "摺疊螢幕")
        ]
        let source = "😀" + terms.map { $0.0 }.joined(separator: "／") + "／屏風／屏東／屏息"
        let result = converter.scan(source)
        let manual = result.occurrences.filter { $0.kind == .manual }
        try check(manual.map(\.from) == terms.map { $0.0 }, "七種螢幕詞形都應列為手動替換建議。")
        try check(manual.map(\.to) == terms.map { $0.1 }, "七種螢幕詞形都應轉成指定的臺灣用語。")
        try check(manual.allSatisfy { !$0.contextual }, "螢幕詞是直接替換詞，不應標成需看情境。")

        var expectedStarts: [Int] = []
        var offset = 2
        for (from, _) in terms {
            expectedStarts.append(offset)
            offset += from.utf16.count + 1
        }
        try check(manual.map(\.startUTF16) == expectedStarts, "含 emoji 的螢幕詞位置必須使用原文 UTF-16 偏移。")
        try check(manual.map(\.endUTF16) == zip(expectedStarts, terms).map { $0.0 + $0.1.0.utf16.count }, "螢幕詞結束位置必須是 UTF-16 半開區間。")

        let replaced = converter.replaceAll(in: result)
        let expectedOutput = "😀" + terms.map { $0.1 }.joined(separator: "／") + "／屏風／屏東／屏息"
        try check(converter.output(for: replaced) == expectedOutput, "螢幕詞完整片語替換後，其他含「屏」用語必須保留。")
        try check(replaced.occurrences.filter { $0.kind == .manual }.allSatisfy { $0.applied }, "全部替換應套用七組非情境螢幕詞。")
        try check(!result.occurrences.contains { ["屏風", "屏東", "屏息"].contains($0.from) }, "屏風、屏東、屏息不得誤列為螢幕詞。")
        var roundTrip = replaced
        for occurrence in manual.reversed() {
            roundTrip = converter.toggleOccurrence(atUTF16Offset: occurrence.startUTF16, in: roundTrip)
        }
        try check(converter.output(for: roundTrip) == source, "完整螢幕片語逐處還原後必須回到原文。")

        let repeated = converter.scan("😀全屏全屏")
        try check(repeated.occurrences.filter { $0.kind == .manual }.map(\.startUTF16) == [2, 4], "重複螢幕詞的位置須保留 emoji 的 UTF-16 長度。")
        let first = converter.toggleOccurrence(atUTF16Offset: 2, in: repeated)
        try check(converter.output(for: first) == "😀全螢幕全屏", "重複螢幕詞應能單獨套用第一處。")
        let both = converter.toggleOccurrence(atUTF16Offset: 4, in: first)
        try check(converter.output(for: both) == "😀全螢幕全螢幕", "重複螢幕詞應能再單獨套用第二處。")
        let secondOnly = converter.toggleOccurrence(atUTF16Offset: 2, in: both)
        try check(converter.output(for: secondOnly) == "😀全屏全螢幕", "重複螢幕詞切回第一處時不得撤銷第二處。")
        let none = converter.toggleOccurrence(atUTF16Offset: 4, in: secondOnly)
        try check(converter.output(for: none) == "😀全屏全屏", "重複螢幕詞應能逐處還原至原文。")

        let mixed = converter.scan("😀外屏與电脑鼠标")
        let mixedManual = mixed.occurrences.first { $0.kind == .manual }
        let mixedOpenCC = mixed.occurrences.filter { $0.kind == .openCC }
        try check(mixedManual?.from == "外屏" && mixedManual?.startUTF16 == 2, "自訂螢幕詞須保留混合內容中的 UTF-16 位置。")
        try check(mixedOpenCC.map(\.from) == ["电脑鼠标"] && mixedOpenCC.map(\.to) == ["電腦滑鼠"], "螢幕詞旁邊的 OpenCC 臺灣詞組仍應提供建議。")
        try check(converter.output(for: converter.replaceAll(in: mixed)) == "😀外螢幕與電腦滑鼠", "自訂螢幕詞與相鄰 OpenCC 建議應可一併替換。")
    }

    private static func checkLongestOverlapAndUTF16Offsets() throws {
        let converter = Converter(dictionary: [
            entry(from: "台", to: "臺"),
            entry(from: "台灣", to: "臺灣")
        ], usesOpenCC: false)
        let result = converter.scan("😀台灣\n台")
        try check(result.occurrences.map(\.from) == ["台灣", "台"], "重疊字詞必須先取最長的一組。")
        try check(result.occurrences.map(\.startUTF16) == [2, 5], "位置必須使用 UTF-16，並保留 emoji 與換行的長度。")
        try check(result.occurrences.map(\.endUTF16) == [4, 6], "結束位置必須是 UTF-16 的半開區間。")
    }

    private static func checkIndependentToggleAndUndo() throws {
        let converter = Converter()
        let scanned = converter.scan("😀視頻\n視頻")
        try check(scanned.occurrences.map(\.startUTF16) == [2, 5], "重複詞位置應分開，且用 UTF-16 計算。")
        let firstApplied = converter.toggleOccurrence(atUTF16Offset: 2, in: scanned)
        try check(converter.output(for: firstApplied) == "😀影片\n視頻", "逐處替換應只改第一處。")
        try check(firstApplied.occurrences.map(\.applied) == [true, false], "兩處相同詞仍須有獨立套用狀態。")
        let undone = converter.toggleOccurrence(atUTF16Offset: 2, in: firstApplied)
        try check(converter.output(for: undone) == "😀視頻\n視頻", "逐處還原應恢復原文。")
    }

    private static func checkContextualReplaceAll() throws {
        let converter = Converter()
        let result = converter.replaceAll(in: converter.scan("文件夾／股票代碼／代碼"))
        try check(converter.output(for: result) == "資料夾／股票代碼／代碼", "全部替換必須略過需看情境的詞。")
        try check(result.occurrences.map(\.applied) == [true, false, false], "情境詞必須保持未套用。")
    }

    private static func checkOpenCCExceptions() throws {
        let converter = Converter(dictionary: [])
        let kept = ["權限", "參數", "參數表", "性價比", "映射", "像素"]
        for word in kept {
            let result = converter.replaceAll(in: converter.scan("設定\(word)與"))
            try check(converter.output(for: result) == "設定\(word)與", "例外詞「\(word)」不應被 OpenCC 改寫。")
        }
        let simplified = converter.replaceAll(in: converter.scan("权限与参数"))
        try check(converter.output(for: simplified) == "權限與參數", "簡體例外詞仍須轉成繁體，但不改成台灣替代詞。")
        let others = converter.replaceAll(in: converter.scan("鼠标"))
        try check(converter.output(for: others) == "滑鼠", "例外詞典不可影響其他 OpenCC 台灣詞組。")
        let bytes = converter.replaceAll(in: converter.scan("字节与字節，字节跳动"))
        try check(converter.output(for: bytes) == "位元組與位元組，字節跳動", "字節須轉成位元組，只有字節跳動保留。")
        let web = converter.replaceAll(in: converter.scan("经营销售，发布会，發布會，发布，账号，营销，后台，运营，官宣，点击"))
        try check(converter.output(for: web) == "經營銷售，發表會，發表會，發布，帳號，行銷，後台，營運，官方宣傳，點選", "網路文章常見詞須轉成台灣用語。")
        let audit: [(String, String)] = [
            ("游戏类型", "遊戲類型"), ("刷新纪录", "刷新紀錄"), ("回归国家队", "回歸國家隊"),
            ("技术文件", "技術文件"), ("文件夹与文件名", "資料夾與檔名"), ("窗口期", "窗口期"), ("促进局部血液循环", "促進局部血液循環"),
            ("差额选举程序", "差額選舉程序"), ("延缓脑萎缩进展", "延緩腦萎縮進展"),
            ("小米YU7对比特斯拉", "小米YU7對比特斯拉"), ("从字节和腾讯拿到", "從字節和騰訊拿到"),
            ("比特摩尔锦标赛", "比特摩爾錦標賽"), ("重装上阵", "重裝上陣"),
            ("中央广播电视总台", "中央廣播電視總台"), ("别只顾方便", "別只顧方便"),
            ("分区收纳", "分區收納"), ("打视频电话", "打視訊電話"), ("基金代码", "基金代碼"),
            ("免责声明，联合声明", "免責聲明，聯合聲明"),
            ("社区养老，中文社区，开源社区，技术社区，开发者生态社区，网络社区", "社區養老，中文社群，開源社群，技術社群，開發者生態社群，網路社群"),
            ("万象城，王者万象棋", "萬象城，王者萬象棋"), ("长城欧拉，欧拉公式", "長城歐拉，尤拉公式"),
            ("加纳乔，加纳", "加納喬，迦納"), ("华为余承东", "華為余承東"),
            ("外卖，公交车，公交站，小区，点赞，户型，楼盘", "外送，公車，公車站，社區，按讚，格局，建案"),
            ("无人驾驶出租车", "無人駕駛計程車"), ("驾驶员下车，安全驾驶员", "駕駛下車，安全駕駛"),
            ("美国历史，中国历代，美国历经，旭日东升", "美國歷史，中國歷代，美國歷經，旭日東昇"),
            ("消费维权数据报告", "消費維權數據報告"), ("核光钟运行", "核光鐘運行"),
            ("安徽新华发行", "安徽新華發行"), ("网签户型", "網簽格局"), ("连接线转接卡", "連接線轉接卡"),
            ("ZOL中关村在线", "ZOL中關村在線"), ("中国抛出的橄榄枝", "中國拋出的橄欖枝"),
            ("短暂回调，集体回调", "短暫回調，集體回調"), ("从后宫扩展到市井，Type-C扩展坞，修改扩展名", "從後宮擴展到市井，Type-C擴充座，修改副檔名"),
            ("电话卡注销，回购注销", "電話卡註銷，回購註銷"),
            ("工业化进程，现代化进程，和平进程，历史进程", "工業化進程，現代化進程，和平進程，歷史進程"),
            ("高级教师，高级记者，高级职称，正高级专业技术，高级礼包", "高級教師，高級記者，高級職稱，正高級專業技術，高級禮包"),
            ("靠性价比打开市场", "靠性價比打開市場"), ("东升地区", "東升地區"),
            ("经济运行，高景气运行", "經濟運行，高景氣運行")
        ]
        for (source, wanted) in audit {
            let result = converter.replaceAll(in: converter.scan(source))
            try check(converter.output(for: result) == wanted, "網路文章實測：「\(source)」應轉成「\(wanted)」。")
        }
        let full = Converter()
        let manual = full.replaceAll(in: full.scan("默认了，二维码，性价比，性價比"))
        try check(full.output(for: manual) == "預設了，QR Code，C/P 值，C/P 值", "人工詞庫須處理默认、二维码與性價比。")
    }

    private static func checkQualityIsContextual() throws {
        let converter = Converter()
        for word in ["质量", "質量"] {
            let result = converter.scan("\(word)很好")
            try check(result.occurrences.first?.to == "品質" && result.occurrences.first?.contextual == true, "「\(word)」須建議品質並列為需看情境。")
            try check(converter.output(for: converter.replaceAll(in: result)) == "\(word)很好", "全部替換時「\(word)」須保留原文。")
        }
    }

    private static func checkOpenCCSuggestionsAndOffsets() throws {
        let converter = Converter()
        let source = "😀视频 / 鼠标\nOpenCC stays English"
        let result = converter.scan(source)
        try check(result.openCCError == nil, "官方 OpenCC 资源必須成功載入並掃描。")
        let suggestions = result.occurrences.filter { $0.kind == .openCC }
        try check(suggestions.map(\.from) == ["视频", "鼠标"], "OpenCC 必須補上內建 16 組詞庫沒有的簡體用語建議。")
        try check(suggestions.map(\.to) == ["影片", "滑鼠"], "s2twp 必須採用 OpenCC 臺灣慣用詞。")
        try check(suggestions.map(\.startUTF16) == [2, 7], "OpenCC 建議位置必須保留 emoji 與混合文字的 UTF-16 偏移。")

        let firstApplied = converter.toggleOccurrence(atUTF16Offset: 2, in: result)
        try check(converter.output(for: firstApplied) == "😀影片 / 鼠标\nOpenCC stays English", "OpenCC 逐處替換應只套用第一處。")
        let bothApplied = converter.toggleOccurrence(atUTF16Offset: 7, in: firstApplied)
        try check(converter.output(for: bothApplied) == "😀影片 / 滑鼠\nOpenCC stays English", "第二處 OpenCC 建議應可獨立套用。")
        let secondOnly = converter.toggleOccurrence(atUTF16Offset: 2, in: bothApplied)
        try check(converter.output(for: secondOnly) == "😀视频 / 滑鼠\nOpenCC stays English", "還原 OpenCC 建議應保留另一處已套用結果。")

        let repeated = converter.scan("😀视频视频")
        let repeatedSuggestions = repeated.occurrences.filter { $0.kind == .openCC }
        try check(repeatedSuggestions.map(\.startUTF16) == [2, 4], "重複的 OpenCC 詞組必須保留個別位置。")
        let repeatedFirstOnly = converter.toggleOccurrence(atUTF16Offset: 2, in: repeated)
        try check(converter.output(for: repeatedFirstOnly) == "😀影片视频", "重複詞的第一個 OpenCC 建議必須能獨立套用。")
        let repeatedBoth = converter.toggleOccurrence(atUTF16Offset: 4, in: repeatedFirstOnly)
        try check(converter.output(for: repeatedBoth) == "😀影片影片", "重複詞的第二個 OpenCC 建議必須能獨立套用。")
        let repeatedSecondOnly = converter.toggleOccurrence(atUTF16Offset: 2, in: repeatedBoth)
        try check(converter.output(for: repeatedSecondOnly) == "😀视频影片", "還原重複詞的第一個建議不得撤銷第二個。")

        let compatibility = converter.scan("你😀视频 / 鼠标")
        try check(compatibility.openCCError == nil, "相容漢字正規化後仍須成功掃描。")
        let compatibilitySuggestions = compatibility.occurrences.filter { $0.kind == .openCC }
        try check(compatibilitySuggestions.map(\.from) == ["你", "视频", "鼠标"], "BMP／補充平面正規化與後續詞組必須都可提供建議。")
        try check(compatibilitySuggestions.map(\.to) == ["你", "影片", "滑鼠"], "相容漢字輸出及臺灣詞組必須符合 OpenCC。")
        try check(compatibilitySuggestions.map(\.startUTF16) == [0, 4, 9], "正規化字元寬度改變後仍須保留原文 UTF-16 位置。")

        let singleCharacter = converter.scan("屏")
        try check(singleCharacter.occurrences.isEmpty, "OpenCC 不可把單字「屏」盲目改成其他字。")
    }

    private static func checkOpenCCPhraseCoverage() throws {
        let openCCOnly = Converter(dictionary: [], usesOpenCC: true)
        let traditional = openCCOnly.scan("繁體視頻／全屏")
        let traditionalSuggestions = traditional.occurrences.filter { $0.kind == .openCC }
        try check(traditionalSuggestions.map(\.from) == ["視頻"], "s2twp 必須能處理既有繁體輸入的臺灣詞組。")
        try check(traditionalSuggestions.map(\.to) == ["影片"], "繁體「視頻」應由 OpenCC 臺灣詞組轉成「影片」。")
        try check(openCCOnly.output(for: openCCOnly.replaceAll(in: traditional)) == "繁體影片／全屏", "全屏用法不在這輪 OpenCC 的變更範圍內，必須保留原文。")

        let simplified = openCCOnly.scan("简体视频／全屏")
        try check(openCCOnly.output(for: openCCOnly.replaceAll(in: simplified)) == "簡體影片／全屏", "簡體輸入應轉成臺灣字形與詞組；「全屏」維持原樣。")
    }

    private static func checkContextualEntriesAreProtectedFromOpenCC() throws {
        let converter = Converter()
        let source = "股票代碼／信息／用戶／支持／數據"
        let scanned = converter.scan(source)
        let contextual = scanned.occurrences.filter { $0.kind == .manual && $0.contextual }
        try check(contextual.map(\.from) == ["代碼", "信息", "用戶", "支持", "數據"], "現有情境詞必須在原文中保留為手動建議。")

        let replaced = converter.replaceAll(in: scanned)
        try check(converter.output(for: replaced) == source, "OpenCC 全部替換不得越過需看情境的內建詞。")
        try check(contextual.allSatisfy { occurrence in
            replaced.occurrences.first(where: { $0.startUTF16 == occurrence.startUTF16 })?.applied == false
        }, "全部替換後情境詞仍須維持未套用。")

        let simplifiedAliases = converter.scan("股票代码／用户数据")
        try check(converter.output(for: converter.replaceAll(in: simplifiedAliases)) == "股票程式碼／使用者資料", "OpenCC 會轉換沒有精確符合繁體情境詞表的簡體別形。")
    }

    private static func checkContextualOverlapKeepsOtherOpenCCSuggestions() throws {
        let converter = Converter()
        let source = "股票代碼與电脑鼠标"
        let scanned = converter.scan(source)
        let contextual = scanned.occurrences.first { $0.kind == .manual && $0.contextual }
        let openCC = scanned.occurrences.filter { $0.kind == .openCC }
        try check(contextual?.from == "代碼", "混合文字中的繁體情境詞必須保留手動審閱項目。")
        try check(openCC.map(\.from) == ["电脑鼠标"], "略過情境詞時仍須保留同一段中其他 OpenCC 變更。")
        try check(openCC.map(\.to) == ["電腦滑鼠"], "OpenCC 未與情境詞重疊的變更應保留。")
        try check(converter.output(for: converter.replaceAll(in: scanned)) == "股票代碼與電腦滑鼠", "全部替換應只轉換未與情境詞重疊的 OpenCC 片段。")
    }

    private static func checkSourceEditResetsState() throws {
        var session = DocumentSession(sourceText: "視頻")
        session.scan()
        session.toggleOccurrence(atUTF16Offset: 0)
        try check(session.output == "影片", "前置替換應成功，才能檢查重置。")
        session.setSourceText("新的文件夾")
        try check(session.result == nil && session.output == nil, "修改原文後必須清除舊掃描和套用狀態。")
        session.scan()
        try check(session.output == "新的文件夾", "新掃描初始狀態不能沿用舊替換。")
    }

    private static func checkUTF8Decoding() throws {
        let decoded = try UTF8Text.decode(Data("繁體 😀".utf8))
        try check(decoded == "繁體 😀", "有效 UTF-8 文字必須完整解碼。")
        do {
            _ = try UTF8Text.decode(Data([0xC3, 0x28]))
            throw CheckFailure(description: "無效 UTF-8 必須回報錯誤。")
        } catch is UTF8TextError {
            // Expected: invalid UTF-8 must not silently become replacement characters.
        }
    }

    private static func entry(from: String, to: String, contextual: Bool = false) -> DictionaryEntry {
        DictionaryEntry(from: from, to: to, note: "測試", tip: "提示", example: "例句", contextual: contextual)
    }
}

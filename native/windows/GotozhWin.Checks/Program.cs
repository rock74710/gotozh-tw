using GotozhWin.Core;

// Windows 視窗版共用邏輯的驗收；可選擇以第一個參數指定 gotozh.exe 做實際掃描。
var failures = 0;

void Check(string name, bool ok)
{
    Console.WriteLine($"{(ok ? "通過" : "失敗")}：{name}");
    if (!ok) failures++;
}

const string scanJson = """
{
  "occurrences" : [
    { "contextual" : false, "endUTF16" : 2, "from" : "卖", "kind" : "openCC", "startUTF16" : 1, "to" : "送" },
    { "contextual" : true, "endUTF16" : 6, "from" : "视频", "kind" : "manual", "startUTF16" : 4, "to" : "影片" },
    { "contextual" : false, "endUTF16" : 10, "from" : "文件夹", "kind" : "manual", "startUTF16" : 7, "to" : "資料夾" }
  ],
  "sourceUTF16Length" : 11
}
""";
// 「😀」佔兩個 UTF-16 單位，確認位置與 Swift 核心一致。
const string source = "外卖😀视频与文件夹。";

var result = ScanResult.Parse(source, scanJson);
Check("讀取掃描 JSON", result.Occurrences.Count == 3 && result.OpenCCError == null);
Check("未替換時輸出原文", DocumentSession.Output(result) == source);

DocumentSession.ReplaceAll(result);
Check("全部替換略過情境詞", DocumentSession.Output(result) == "外送😀视频与資料夾。");

DocumentSession.Toggle(result, 4);
Check("逐處替換情境詞", DocumentSession.Output(result) == "外送😀影片与資料夾。");

DocumentSession.Toggle(result, 1);
Check("逐處還原", DocumentSession.Output(result) == "外卖😀影片与資料夾。");

Check("前後文標出詞語", DocumentSession.Context(source, result.Occurrences[1], 2) == "…😀「视频」与文…");

var mismatch = false;
try { ScanResult.Parse("短", scanJson); } catch (FormatException) { mismatch = true; }
Check("原文長度不符時拒絕", mismatch);

// WinUI 文字框把所有換行存成單一 \r，複製與儲存前要換回 Windows 的 \r\n。
Check("輸出換行改成 Windows 格式", DocumentSession.WithWindowsNewlines("甲\r乙\r\n丙\n") == "甲\r\n乙\r\n丙\r\n");

if (args.Length == 1)
{
    var runner = new GotozhRunner(args[0]);
    var live = await runner.ScanAsync("外卖驾驶员");
    DocumentSession.ReplaceAll(live);
    Check("實際呼叫 gotozh.exe", DocumentSession.Output(live) == "外送駕駛");
    Check("讀取內建詞庫", runner.LoadDictionary().ContainsKey("服務器"));
}

Console.WriteLine(failures == 0 ? "全部 Windows 視窗版驗收通過。" : $"{failures} 項失敗。");
return failures == 0 ? 0 : 1;

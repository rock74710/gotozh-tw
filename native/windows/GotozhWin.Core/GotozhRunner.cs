using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace GotozhWin.Core;

public sealed class DictionaryEntry
{
    [JsonPropertyName("from")] public string From { get; init; } = "";
    [JsonPropertyName("to")] public string To { get; init; } = "";
    [JsonPropertyName("note")] public string Note { get; init; } = "";
    [JsonPropertyName("tip")] public string Tip { get; init; } = "";
    [JsonPropertyName("example")] public string Example { get; init; } = "";
    [JsonPropertyName("contextual")] public bool Contextual { get; init; }
}

// 在背景執行 gotozh.exe scan，文字經標準輸入以 UTF-8 傳送，不寫暫存檔。
public sealed class GotozhRunner
{
    private const string BundleName = "GotozhNative_GotozhCore.bundle";
    private static readonly UTF8Encoding Utf8 = new(false);
    public string ExecutablePath { get; }

    public GotozhRunner(string executablePath) => ExecutablePath = executablePath;

    public async Task<ScanResult> ScanAsync(string source)
    {
        var info = new ProcessStartInfo(ExecutablePath, "scan")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardInputEncoding = Utf8,
            StandardOutputEncoding = Utf8,
            StandardErrorEncoding = Utf8,
        };

        Process process;
        try
        {
            process = Process.Start(info) ?? throw new InvalidOperationException("無法啟動 gotozh.exe。");
        }
        catch (System.ComponentModel.Win32Exception)
        {
            throw new InvalidOperationException($"找不到或無法執行 {ExecutablePath}。");
        }

        using (process)
        {
            var output = process.StandardOutput.ReadToEndAsync();
            var error = process.StandardError.ReadToEndAsync();
            await process.StandardInput.WriteAsync(source);
            process.StandardInput.Close();
            await process.WaitForExitAsync();

            if (process.ExitCode == -1073741515)
                throw new InvalidOperationException("gotozh.exe 找不到 Swift 執行環境的 DLL，請確認已安裝 Swift 或把執行環境放在同一資料夾。");
            if (process.ExitCode != 0)
                throw new InvalidOperationException($"gotozh.exe 掃描失敗（代碼 {process.ExitCode}）：{(await error).Trim()}");
            return ScanResult.Parse(source, await output);
        }
    }

    // 詞條說明直接讀 gotozh.exe 旁的字典檔，與命令列工具用同一份資料。
    public Dictionary<string, DictionaryEntry> LoadDictionary()
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(ExecutablePath)) ?? ".";
        var path = Path.Combine(directory, BundleName, "manual-dictionary.json");
        var entries = JsonSerializer.Deserialize<List<DictionaryEntry>>(File.ReadAllText(path, Utf8)) ?? new();
        return entries.ToDictionary(e => e.From);
    }
}

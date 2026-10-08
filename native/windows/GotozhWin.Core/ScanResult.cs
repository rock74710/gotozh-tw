using System.Text.Json;
using System.Text.Json.Serialization;

namespace GotozhWin.Core;

// 對應 gotozh scan 的 JSON；位置以 UTF-16 半開區間表示，與 C# 字串索引相同。
public sealed class Occurrence
{
    [JsonPropertyName("startUTF16")] public int StartUtf16 { get; init; }
    [JsonPropertyName("endUTF16")] public int EndUtf16 { get; init; }
    [JsonPropertyName("from")] public string From { get; init; } = "";
    [JsonPropertyName("to")] public string To { get; init; } = "";
    [JsonPropertyName("contextual")] public bool Contextual { get; init; }
    [JsonPropertyName("kind")] public string Kind { get; init; } = "";
    [JsonIgnore] public bool Applied { get; set; }
}

public sealed class ScanResult
{
    public string Source { get; }
    public List<Occurrence> Occurrences { get; }
    public string? OpenCCError { get; }

    private ScanResult(string source, List<Occurrence> occurrences, string? openCCError)
    {
        Source = source;
        Occurrences = occurrences;
        OpenCCError = openCCError;
    }

    private sealed class Payload
    {
        [JsonPropertyName("sourceUTF16Length")] public int SourceUtf16Length { get; init; }
        [JsonPropertyName("occurrences")] public List<Occurrence> Occurrences { get; init; } = new();
        [JsonPropertyName("openCCError")] public string? OpenCCError { get; init; }
    }

    public static ScanResult Parse(string source, string json)
    {
        var payload = JsonSerializer.Deserialize<Payload>(json)
            ?? throw new FormatException("gotozh 沒有輸出掃描結果。");
        // 長度不符代表送出與收到的文字不同（例如編碼錯誤），位置不能使用。
        if (payload.SourceUtf16Length != source.Length)
            throw new FormatException("gotozh 收到的文字與原文長度不同，可能是編碼錯誤。");
        return new ScanResult(source, payload.Occurrences, payload.OpenCCError);
    }
}

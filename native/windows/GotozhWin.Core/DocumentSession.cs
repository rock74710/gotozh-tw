using System.Text;
using System.Text.RegularExpressions;

namespace GotozhWin.Core;

// 與 Swift 核心 Converter 的 toggle／replaceAll／output 相同規則。
public static class DocumentSession
{
    public static void Toggle(ScanResult result, int startUtf16)
    {
        var occurrence = result.Occurrences.FirstOrDefault(o => o.StartUtf16 == startUtf16);
        if (occurrence != null) occurrence.Applied = !occurrence.Applied;
    }

    public static void ReplaceAll(ScanResult result)
    {
        foreach (var occurrence in result.Occurrences.Where(o => !o.Contextual))
            occurrence.Applied = true;
    }

    public static string Output(ScanResult result)
    {
        var source = result.Source;
        if (!result.Occurrences.Any(o => o.Applied)) return source;

        var builder = new StringBuilder();
        var cursor = 0;
        foreach (var occurrence in result.Occurrences)
        {
            if (occurrence.StartUtf16 < cursor || occurrence.EndUtf16 > source.Length) continue;
            builder.Append(source, cursor, occurrence.StartUtf16 - cursor);
            builder.Append(occurrence.Applied
                ? occurrence.To
                : source[occurrence.StartUtf16..occurrence.EndUtf16]);
            cursor = occurrence.EndUtf16;
        }
        builder.Append(source, cursor, source.Length - cursor);
        return builder.ToString();
    }

    // WinUI 文字框把換行都存成 \r；寫檔或複製前統一成 Windows 的 \r\n。
    public static string WithWindowsNewlines(string text) =>
        Regex.Replace(text, @"\r\n|\r|\n", "\r\n");

    public static string Context(string source, Occurrence occurrence, int radius = 14)
    {
        var start = Math.Max(0, occurrence.StartUtf16 - radius);
        var end = Math.Min(source.Length, occurrence.EndUtf16 + radius);
        // 不把 emoji 等兩個單位的字切成一半。
        if (start > 0 && start < source.Length && char.IsLowSurrogate(source[start]) && char.IsHighSurrogate(source[start - 1]))
            start--;
        if (end > 0 && end < source.Length && char.IsHighSurrogate(source[end - 1]) && char.IsLowSurrogate(source[end]))
            end++;

        var before = Regex.Replace(source[start..occurrence.StartUtf16], @"\s+", " ");
        var after = Regex.Replace(source[occurrence.EndUtf16..end], @"\s+", " ");
        return $"{(start > 0 ? "…" : "")}{before}「{occurrence.From}」{after}{(end < source.Length ? "…" : "")}";
    }
}

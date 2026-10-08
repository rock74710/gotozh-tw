using System.Text;
using GotozhWin.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Pickers;

namespace GotozhWin;

// 逐處建議清單的一列；文字已在建立時組好，畫面只負責顯示。
public sealed class SuggestionRow
{
    public int Start { get; init; }
    public string From { get; init; } = "";
    public string To { get; init; } = "";
    public string Badge { get; init; } = "";
    public Brush BadgeBrush { get; init; } = new SolidColorBrush(Colors.Transparent);
    public string State { get; init; } = "";
    public string Context { get; init; } = "";
    public string Tip { get; init; } = "";
    public string Example { get; init; } = "";
    public Visibility ExampleVisibility => Example.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    public string ButtonLabel { get; init; } = "";
}

public sealed partial class MainWindow : Window
{
    private static readonly UTF8Encoding Utf8 = new(false);

    private readonly Brush contextualBrush = new SolidColorBrush(ColorHelper.FromArgb(0x40, 0xF2, 0xA0, 0x2C));
    private readonly Brush openCCBrush = new SolidColorBrush(ColorHelper.FromArgb(0x30, 0x3A, 0x7B, 0xD5));
    private readonly Brush manualBrush = new SolidColorBrush(ColorHelper.FromArgb(0x30, 0x2E, 0x6B, 0x4F));
    private readonly GotozhRunner runner = new(Path.Combine(AppContext.BaseDirectory, "gotozh.exe"));
    private readonly Dictionary<string, DictionaryEntry> entries = new();
    private ScanResult? result;

    public MainWindow()
    {
        InitializeComponent();
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1100, 760));
        try
        {
            entries = runner.LoadDictionary();
            SuggestionHint.Text = $"內建 {entries.Count} 組詞＋OpenCC 臺灣正體與慣用詞建議・情境詞會略過全部替換";
        }
        catch (Exception error)
        {
            SuggestionHint.Text = "讀不到內建詞庫說明：" + error.Message;
        }
    }

    private string? OutputText => result == null ? null : DocumentSession.Output(result);

    private void SourceBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        SourceCount.Text = $"{SourceBox.Text.Length} 字";
        // 原文改了，舊的位置不能再用，必須重新掃描。
        if (result != null && result.Source != SourceBox.Text)
        {
            result = null;
            Refresh("原文已修改，請重新掃描。");
        }
    }

    private async void Scan_Click(object sender, RoutedEventArgs e)
    {
        var source = SourceBox.Text;
        ScanButton.IsEnabled = false;
        try
        {
            result = await runner.ScanAsync(source);
            // 掃描期間原文又被修改時，丟掉這次結果。
            if (SourceBox.Text != source) result = null;
            Refresh(null);
        }
        catch (Exception error)
        {
            result = null;
            Refresh(null);
            await ShowError(error.Message);
        }
        finally
        {
            ScanButton.IsEnabled = true;
        }
    }

    private void ReplaceAll_Click(object sender, RoutedEventArgs e)
    {
        if (result == null) return;
        DocumentSession.ReplaceAll(result);
        Refresh(null);
    }

    private void Toggle_Click(object sender, RoutedEventArgs e)
    {
        if (result == null || sender is not Button { Tag: int start }) return;
        DocumentSession.Toggle(result, start);
        Refresh(null);
    }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        if (OutputText is not { } text) return;
        var package = new DataPackage();
        package.SetText(DocumentSession.WithWindowsNewlines(text));
        Clipboard.SetContent(package);
    }

    private async void OpenFile_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".txt");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync();
        if (file == null) return;
        try
        {
            var bytes = await File.ReadAllBytesAsync(file.Path);
            SourceBox.Text = new UTF8Encoding(false, true).GetString(bytes).TrimStart('﻿');
        }
        catch (DecoderFallbackException)
        {
            await ShowError("這個檔案不是 UTF-8 文字檔。");
        }
        catch (Exception error)
        {
            await ShowError(error.Message);
        }
    }

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        if (OutputText is not { } text)
        {
            await ShowError("請先掃描文字，再儲存轉換結果。");
            return;
        }
        var picker = new FileSavePicker { SuggestedFileName = "轉換結果" };
        picker.FileTypeChoices.Add("UTF-8 文字檔", new List<string> { ".txt" });
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        var file = await picker.PickSaveFileAsync();
        if (file == null) return;
        try
        {
            await File.WriteAllTextAsync(file.Path, DocumentSession.WithWindowsNewlines(text), Utf8);
        }
        catch (Exception error)
        {
            await ShowError(error.Message);
        }
    }

    private void Refresh(string? message)
    {
        var occurrences = result?.Occurrences ?? new List<Occurrence>();
        var applied = occurrences.Count(o => o.Applied);
        ResultBox.Text = OutputText ?? "";
        ResultSummary.Text = result == null ? "尚未掃描" : $"已替換 {applied} / {occurrences.Count} 處";
        ReplaceAllButton.IsEnabled = occurrences.Any(o => !o.Applied && !o.Contextual);
        CopyButton.IsEnabled = SaveButton.IsEnabled = result != null;

        StatusText.Text = message
            ?? (result == null ? "輸入或開啟文字後，按「開始掃描」查看建議。"
                : result.OpenCCError is { } openCCError ? $"OpenCC 掃描失敗；目前只顯示內建詞庫建議：{openCCError}"
                : occurrences.Count == 0 ? $"沒有找到 OpenCC 或內建詞庫建議。範圍限於 OpenCC 臺灣轉換與 {entries.Count} 組內建詞，請依語意自行確認。"
                : "");
        StatusText.Visibility = StatusText.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        SuggestionList.ItemsSource = result == null ? null : occurrences.Select(MakeRow).ToList();
    }

    private SuggestionRow MakeRow(Occurrence occurrence)
    {
        var entry = occurrence.Kind == "manual" ? entries.GetValueOrDefault(occurrence.From) : null;
        return new SuggestionRow
        {
            Start = occurrence.StartUtf16,
            From = occurrence.From,
            To = occurrence.To,
            Badge = occurrence.Contextual ? "需看情境" : entry != null ? "內建詞庫" : "OpenCC",
            BadgeBrush = occurrence.Contextual ? contextualBrush : entry != null ? manualBrush : openCCBrush,
            State = occurrence.Applied ? "已替換" : "未替換",
            Context = DocumentSession.Context(result!.Source, occurrence),
            Tip = entry != null ? $"{entry.Tip}（{entry.Note}）" : "臺灣正體與慣用詞建議；請依上下文確認。",
            Example = entry != null ? "例：" + entry.Example : "",
            ButtonLabel = occurrence.Applied ? "還原" : "替換",
        };
    }

    private async Task ShowError(string message)
    {
        var dialog = new ContentDialog
        {
            Title = "無法完成",
            Content = message,
            CloseButtonText = "好",
            XamlRoot = Content.XamlRoot,
        };
        await dialog.ShowAsync();
    }
}

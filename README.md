# 講台灣一點（gotozh-tw）

把中國用語換成台灣用語的小工具。貼上一段文字，它會標出「服務器」「視頻」「外卖」這類詞，建議改成「伺服器」「影片」「外送」，讓你逐處確認再替換。

- **網頁版**：https://gotozh-tw.rock74710-8c7.workers.dev ，打開就能用，文章只在你的瀏覽器裡處理，不會上傳。

- **Mac 版與 Windows 版**：到 [Releases](https://github.com/rock74710/gotozh-tw/releases) 下載，可離線使用；另附 `gotozh` 命令列工具。

- **詞庫**：以 [OpenCC](https://github.com/BYVoid/OpenCC) 的台灣詞組為基礎，再加上本專案人工整理的例外詞（例如「文件」保留、「点赞」改成「按讚」）。

## 怎麼用

1. 貼上文字，按「開始掃描」。

2. 黃色是建議修改的詞，可以逐處替換或還原。

3. 按「全部換成台灣用語」，再複製結果。需要看上下文的詞（例如「質量」）不會被自動替換。

## 專案結構

- `native/`：Mac App、`gotozh` 命令列與共用轉換核心（Swift），說明見 [native/README.md](native/README.md)。

- `native/windows/`：Windows 視窗版（C# / WinUI 3），建置步驟見 [native/WINDOWS.md](native/WINDOWS.md)。

## 授權

OpenCC 為 Apache-2.0，授權全文在 `native/Vendor/OpenCC/`。轉換結果只是建議，請自行確認語意。

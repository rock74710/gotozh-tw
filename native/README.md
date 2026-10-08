# Gotozh 原生版

原生版包含 macOS 視窗工具與 `gotozh` 命令列工具，共用同一個離線掃描核心。核心整合 OpenCC v1.4.2 的 C++ 原始碼與同版字典資料，依 Swift Package Manager 建置；執行時不需要 Homebrew、網路或外部 OpenCC 安裝。

內建 30 組人工詞彙保留原有逐處替換與還原功能：原有 16 組維持不變，另加七組螢幕詞，包括「全屏→全螢幕」、「外屏→外螢幕」、「內屏／内屏→內螢幕」和「摺疊屏／折疊屏／折叠屏→摺疊螢幕」。摺疊詞指螢幕本身，不是整支手機。另依網路文章實測加入「默认→預設」、「二维码／二維碼→QR Code」、「性价比／性價比→C/P 值」，以及需看情境的「质量／質量→品質」（物理的質量不改）。OpenCC 會另外提供逐處建議，取代全部時套用一般建議與 OpenCC 建議；和需看情境的人工詞彙重疊的 OpenCC 片段會略過。位置以 UTF-16 零起算半開區間表示。

## OpenCC 詞彙範圍

轉換使用官方 `s2twp` 設定，包含 OpenCC 的簡體轉繁體、臺灣用字與臺灣詞組資料。例如 `视频` 可轉為 `影片`，`鼠标` 可轉為 `滑鼠`；設定也能將既有繁體詞組 `視頻` 轉為 `影片`。官方資料本身不會單獨改寫「屏」或「全屏」；上方七組螢幕詞由本專案的人工詞庫提供。OpenCC 原始碼與字典資料維持上游版本；本專案另加 `TWExceptions.txt` 例外詞典，排在臺灣詞組之前：權限、參數、參數表、性價比、映射、像素保留原詞（簡體仍會轉成繁體）；點擊→點選、发布→發布、发布会→發表會、账号→帳號、营销→行銷、后台→後台、运营→營運、官宣→官方宣傳。依網路文章實測另保留類型、刷新、文件、窗口、局部、循環、分區、聲明等原詞（不轉成型別、重新整理、檔案、視窗、區域性、迴圈、分割槽、宣告），並修正回归→回歸、总台→總台、别只→別只、视频电话→視訊電話、基金代码→基金代碼；文件夾、文件名仍轉成資料夾、檔名。社区保留為社區，但中文社区、开源社区、技术社区、开发者社区、线上社区、生态社区、网络社区、写作社区、讨论社区、兴趣社区、游戏社区、玩家社区轉成社群；万象、长城欧拉、加纳乔、余承东保留原名；外卖→外送、公交→公車、小区→社區、点赞→按讚、户型→格局、楼盘→建案。另加 `STSegments.txt` 斷詞補充，讓「驾驶出租车」能斷出出租车並轉成計程車。掃描只列出原文與建議結果不同的片段。

人工情境詞的保護以原有人工詞條為準：原文中的「代碼、信息、用戶、支持、數據」會列為需審閱項目，全部替換時保留原文。不同字形的簡體輸入可能不會符合這些人工詞條，而直接套用 OpenCC；目前觀察到「股票代码」轉為「股票程式碼」、「用户数据」轉為「使用者資料」。OpenCC 本身依官方字典與片語規則轉換，沒有額外語意判讀；本專案新增詞條存於獨立的人工詞庫。

上游版本、資料版本、第三方相依與授權來源列於 [`Vendor/OpenCC/UPSTREAM.md`](Vendor/OpenCC/UPSTREAM.md)。打包的 App 會在 `Contents/Resources/OpenCC-Licenses/` 保留所有授權文字。

## 建置與驗收

在 `native/` 目錄執行：

```sh
swift build
swift run GotozhChecks
```

`GotozhChecks` 會驗收人工詞庫、重疊字詞、emoji 與 UTF-16 位置、OpenCC 臺灣詞組、相容漢字正規化、簡繁混合內容、重複詞獨立套用與還原、情境詞保護及錯誤 UTF-8。通過時會顯示「全部原生核心驗收通過。」；失敗時以非零狀態結束。

## macOS App

```sh
swift run GotozhMac
```

視窗提供原文、轉換結果和逐處建議，也會說明 OpenCC 的字典轉換範圍。你可以開啟 UTF-8 `.txt` 文字檔、手動掃描、逐處替換或還原、替換全部一般用語、複製結果，或另存轉換結果。拖曳中間分隔線可以調整兩欄寬度；檔案讀寫錯誤或 OpenCC 資源載入問題會顯示在視窗中。

快捷鍵：

- `⌘O` 開啟文字檔；`⌘S` 儲存轉換結果。
- `⌘Return` 開始掃描；`⌘⇧R` 替換全部一般用語。
- `⌘⇧C` 複製轉換結果。

建立本機測試用的未簽署 `.app`：

```sh
sh scripts/package-app.sh
open build/Gotozh.app
```

腳本會建置 release 版本，將 SwiftPM 的 OpenCC 字典資源及授權文字放入 App。若輸出路徑已存在，腳本會停止；請指定新的輸出位置。此包裝未簽署、未公證，適合本機測試。

## 命令列

```sh
swift run gotozh --help
```

`scan` 輸出 JSON；`sourceUTF16Length` 是全文 UTF-16 長度，`startUTF16` 和 `endUTF16` 是每處建議的零起算半開區間。emoji 佔兩個 UTF-16 單位，因此以下「视频」從位置 2 開始：

```sh
printf '😀视频\n代碼' | swift run gotozh scan
```

```json
{
  "occurrences" : [
    {
      "contextual" : false,
      "endUTF16" : 4,
      "from" : "视频",
      "kind" : "openCC",
      "startUTF16" : 2,
      "to" : "影片"
    },
    {
      "contextual" : true,
      "endUTF16" : 7,
      "from" : "代碼",
      "kind" : "manual",
      "startUTF16" : 5,
      "to" : "程式碼"
    }
  ],
  "sourceUTF16Length" : 7
}
```

`convert` 會套用 OpenCC 和一般內建建議，保留需看情境的人工詞條：

```sh
printf '文件夾裡有股票代碼與电脑鼠标' | swift run gotozh convert
```

輸入可從標準輸入讀取，也可指定 UTF-8 檔案；`-` 表示標準輸入：

```sh
swift run gotozh scan ./文章.txt
swift run gotozh convert ./文章.txt > ./文章-轉換結果.txt
cat ./文章.txt | swift run gotozh convert -
```

結果寫到標準輸出，不會改寫輸入檔。未知命令、檔案讀取錯誤、無效 UTF-8 或 OpenCC 轉換失敗會把訊息寫到標準錯誤並以非零狀態結束。

## CLI 互動驗收

建置 `gotozh` 後，可以用 Python 標準庫腳本驗證終端機輸入輸出、JSON 位置、錯誤退出狀態，以及輸入檔不會被改寫：

```sh
python3 scripts/pty-check.py "$(swift build --show-bin-path)/gotozh"
```

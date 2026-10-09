# Windows 版 gotozh 命令列工具（交接說明）

## 狀態

- 已在 Mac 完成：`Package.swift` 改成只在 macOS 建置視窗版 `GotozhMac`；`gotozh` 命令列工具不再依賴 macOS 專用的 `Darwin`。
- Mac 上已驗證：`swift build`、`swift run GotozhChecks` 全部通過，`gotozh convert` 把「外卖驾驶员」轉成「外送駕駛」。
- 2026-10-08 已在 Windows 11 驗證（Swift 6.4.0、Visual Studio 2022 Build Tools）：`swift build`、`swift run GotozhChecks`、`swift build -c release` 全部通過，程式碼不需修改；發行版 `gotozh.exe` 複製到別的資料夾後仍可轉換。以下步驟已依實測結果更正。

## Windows 端步驟

1. 安裝 Swift 6 for Windows（https://www.swift.org/install/windows/ ，會一併要求 Visual Studio 的 C++ 建置工具）。安裝後**開新的終端機視窗**，舊視窗的 PATH 不會更新，會出現找不到 `swift` 或 `link` 的錯誤。

2. 取得程式碼：

   ```powershell
   git clone <NAS 路徑>\Git\gotozh-tw.git
   cd gotozh-tw
   git switch windows
   cd native
   ```

3. 建置與驗收：

   ```powershell
   swift build
   swift run GotozhChecks
   ```

   通過時顯示「全部原生核心驗收通過。」建置時 OpenCC 的 `_CRT_INSECURE_DEPRECATE` 警告，以及「unable to create symbolic link at .build\debug」警告都可以忽略。

4. 試用（Windows PowerShell 5.1）：

   ```powershell
   $OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
   "外卖驾驶员" | swift run gotozh convert
   ```

   預期輸出「外送駕駛」。第一行讓 PowerShell 用 UTF-8 把文字送進程式並顯示結果。只執行 `chcp 65001` 不夠：PowerShell 5.1 仍用 ASCII 傳送管線文字，程式只會收到並輸出「?????」。

5. 發行版：`swift build -c release`。沒有開啟 Windows「開發人員模式」時無法建立 `.build\release` 捷徑，執行檔實際在 `.build\out\Products\Release-windows-x86_64\gotozh.exe`。同一資料夾裡的 `GotozhNative_GotozhCore.bundle` 資料夾（字典檔）必須和 `gotozh.exe` 放在一起，複製到別處時要一起帶走。單獨複製這個 gotozh.exe 時，執行的電腦需要 Swift 執行環境；缺少時程式會直接結束，代碼 -1073741515（找不到 DLL）。要免安裝，請改用下方視窗版的建置輸出（或 `native\dist\windows-x64`），裡面已附 Swift DLL。

## 可能遇到的問題

- OpenCC 的 C++ 原始碼若在 Windows 編譯失敗，先看錯誤是不是出在 `Vendor/OpenCC`；上游 OpenCC 本身支援 Windows，通常是少了某個編譯設定。
- 出現「unable to find bundle named GotozhNative_GotozhCore」時，表示 `GotozhNative_GotozhCore.bundle` 資料夾沒有跟著 `gotozh.exe`。
- 修好後提交到 `windows` 分支並推回 NAS，Mac 這邊再合併。

## Windows 視窗版（GotozhWin）

視窗版用 C# 與 WinUI 3 做畫面，轉換時在背景呼叫上面建置好的 `gotozh.exe`，所以轉換結果和命令列、Mac 版完全一樣。程式在 `windows/` 資料夾：

- `GotozhWin`：視窗程式。

- `GotozhWin.Core`：讀取掃描結果、逐處替換／還原、組出轉換結果的共用邏輯。

- `GotozhWin.Checks`：共用邏輯的驗收程式。

步驟：

1. 安裝 .NET 8 SDK（https://dotnet.microsoft.com/download ）。

2. 先在 `native` 資料夾執行 `swift build -c release`，產生 `gotozh.exe`。視窗版建置時會把它和字典資料夾一起複製過去；找不到時建置會停下並提示。

3. 驗收共用邏輯（最後的參數讓驗收實際呼叫一次 `gotozh.exe`）：

   ```powershell
   cd windows\GotozhWin.Checks
   dotnet run -- ..\..\.build\out\Products\Release-windows-x86_64\gotozh.exe
   ```

   通過時顯示「全部 Windows 視窗版驗收通過。」

4. 建置並開啟視窗：

   ```powershell
   cd ..\GotozhWin
   dotnet build -c Release
   .\bin\Release\net8.0-windows10.0.19041.0\win-x64\GotozhWin.exe
   ```

功能：貼上或開啟 UTF-8 文字檔、開始掃描（Ctrl+Enter）、逐處替換或還原、全部替換一般用語（Ctrl+Shift+R，需看情境的詞會略過）、複製結果（Ctrl+Shift+C）、另存 UTF-8 文字檔（Ctrl+S）。修改原文後舊的掃描結果會清掉，要重新掃描。

注意：

- 視窗版使用 Windows App SDK 2.5.1。舊版 1.6 用 `dotnet build` 會因缺少打包工具而失敗，所以不要降版。

- 目前還不是安裝程式，但整個 `win-x64` 資料夾可直接複製使用：建置時會放入 gotozh.exe 用到的 18 個 Swift／VC++ DLL，並自帶 .NET 8，使用者不必安裝 Swift 或 .NET。DLL 預設取自 `%LOCALAPPDATA%\Programs\Swift\Runtimes\6.4.0\usr\bin`；Swift 版本不同時用 `dotnet build -c Release -p:SwiftRuntimeDir=<資料夾>\` 指定。

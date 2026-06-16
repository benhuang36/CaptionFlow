# CaptionFlow

[English](README.md) | **繁體中文**

macOS 上的即時、全本機字幕與翻譯 app。CaptionFlow 擷取系統音訊、轉成文字、翻譯,
並把原文與譯文以即時字幕呈現 —— **所有運算都在本機**,不經任何雲端服務。唯一會用到
網路的時機,是首次下載語音/翻譯模型。

- **最低系統**:macOS 26
- **音訊擷取**:ScreenCaptureKit(需「螢幕錄製」權限)
- **語音轉文字**:Apple SpeechAnalyzer / SpeechTranscriber,或 WhisperKit(可切換)
- **翻譯**:本機 LLM(MLX + Qwen,品質優先)或 Apple 翻譯(低延遲保底)
- **介面語言**:英文(預設)、繁體中文、簡體中文、日文 —— 跟隨系統語言,並可在 app 內覆蓋

## 運作方式

```
ScreenCaptureKit ─► 系統音訊
        │
        ▼
   STT(串流)──► partial 原文(即時顯示)
        │ 整句 finalize
        ▼
  翻譯(LLM / Apple)──► 譯文
        │
        ▼
     SwiftUI 顯示(雙語 / 只原文 / 只譯文)
```

增量策略:一句話還在講的時候,只有原文即時更新;等 STT 引擎把整句定稿後,才送去翻譯。
所以體感是「原文即時跳字、譯文晚一兩拍補上」。LLM 翻譯還會把前幾句當上下文餵入,
並在輸出沒翻成功時自動重試一次 —— 這對語境依賴的短句、以及破碎的語音辨識輸入幫助很大。

## 功能

- **兩種 STT 引擎** —— Apple SpeechAnalyzer(原生串流、整合最佳)或 WhisperKit
  (`base` / `small` / `large-v3`;多語音訊如日文通常更穩)。
- **兩種翻譯引擎** —— 本機 LLM(MLX + Qwen,品質優先,預設)或 Apple 翻譯(最低延遲/最低記憶體)。
- **依記憶體推薦模型** —— 在記憶體預算內挑品質最高的 Qwen,或自行手動指定。
- **內建下載管理** —— 在設定頁下載、取消、刪除 LLM 與 Whisper 模型。
- **歷史記錄** —— 每次「開始 → 停止」存成一筆,可檢視與複製。
- **顯示模式** —— 雙語、只原文、只譯文。

## 系統需求

- macOS 26
- Xcode 26,含 **Metal Toolchain**(編譯 MLX 必需):
  ```bash
  xcodebuild -downloadComponent MetalToolchain
  ```
- [XcodeGen](https://github.com/yonaskolb/XcodeGen):
  ```bash
  brew install xcodegen
  ```

## 建置與執行

`.xcodeproj` **未**入版控,改用 XcodeGen 從 `project.yml` 產生。clone 後(或每次改了
`project.yml` / 新增檔案時):

```bash
xcodegen generate
open CaptionFlow.xcodeproj
```

接著在 Xcode 按 **▶︎** 執行。建議用 Xcode 跑:它會處理自動簽章,而「螢幕錄製」(TCC)
權限是綁簽章的。

> 首次執行會要求「螢幕錄製」權限。每個 STT/翻譯模型首次使用時會下載(數 GB),
> 之後快取於本機、可離線使用。

## 設定

開啟**設定**可選擇:

- **STT 引擎**,以及(WhisperKit 時)要用哪個模型
- **翻譯引擎**(本機 LLM 或 Apple 翻譯)
- **模型選擇** —— 依記憶體自動推薦,或手動指定
- **語言** —— 介面語言(系統預設、English、繁體中文、简体中文、日本語)

來源/目標語言與顯示模式則在主畫面的控制列設定。

## 專案結構

| 目錄 | 內容 |
|---|---|
| `App/` | App 進入點 |
| `Audio/` | ScreenCaptureKit 擷取、緩衝轉檔、音量量測 |
| `Speech/` | STT 協定 + SpeechAnalyzer 與 WhisperKit 轉錄器 |
| `Translation/` | 翻譯協定 + MLX/Qwen 與 Apple 翻譯服務 |
| `ModelManagement/` | 硬體分析、模型推薦、下載管理 |
| `Pipeline/` | `CaptionPipeline` 串接整條流程 |
| `Views/` | 主畫面、控制列、字幕列表、設定、歷史 |
| `Models/` | `Language`、`DisplayMode`、`CaptionSegment`、`LLMModel`、歷史型別 |
| `Settings/` | `AppSettings`(UserDefaults)、在地化 helper |
| `Resources/` | String Catalog(`Localizable.xcstrings`、`InfoPlist.xcstrings`) |
| `scripts/` | `package.sh`(建置+簽章+打包)、`gen_xcstrings.py`(重新產生 catalog) |

## 隱私

所有轉錄與翻譯都在裝置端進行。CaptionFlow 不會把音訊或文字送到任何伺服器。唯一的對外
網路請求,是首次使用時從 Hugging Face 下載模型。

## 授權

[MIT](LICENSE)

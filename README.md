# CaptionFlow

擷取 macOS 系統音訊,即時顯示原文與譯文的字幕 app。全本機運算(STT + 翻譯),不需連網。

- **最低系統**:macOS 26
- **音訊截取**:ScreenCaptureKit(需螢幕錄製權限)
- **語音轉文字**:SpeechAnalyzer / SpeechTranscriber(備援:WhisperKit)
- **翻譯**:本機 LLM(MLX + Qwen,品質優先)/ Apple Translation(低延遲保底)

## 產生並開啟專案

未提交 `.xcodeproj`,改用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 從 `project.yml` 產生:

```bash
brew install xcodegen      # 若尚未安裝
xcodegen generate
open CaptionFlow.xcodeproj
```

## 現況:可執行的骨架

按「開始」即可看到 UI 運作 —— 目前走 **mock 服務**(假字幕 + 假翻譯),
所以**不需要任何權限,也不需要下載模型**。真實的 ML 接點都已就位、標了 `TODO`。

切換到真實 pipeline:把 [`CaptionPipeline`](CaptionFlow/Pipeline/CaptionPipeline.swift)
的 `useMockServices` 設為 `false`,然後依下列接點填實作。

## 架構

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

| 目錄 | 內容 |
|---|---|
| `App/` | App 進入點 |
| `Models/` | `Language`、`DisplayMode`、`CaptionSegment`、`LLMModel` |
| `ModelManagement/` | 依記憶體推薦模型(`HardwareProfiler`、`ModelRecommender`、`ModelManager`) |
| `Audio/` | `AudioCaptureService` 協定 + ScreenCaptureKit 實作 |
| `Speech/` | STT 協定 + SpeechAnalyzer 接點 + Mock |
| `Translation/` | 翻譯協定 + MLX / Apple 接點 + Mock |
| `Pipeline/` | `CaptionPipeline` 串接整條流程 |
| `Views/` | 主畫面、控制列、字幕列表、設定 |
| `Settings/` | `AppSettings`(UserDefaults 持久化) |

## 待接上的真實實作(TODO)

1. **STT** — [`SpeechAnalyzerTranscriber`](CaptionFlow/Speech/SpeechAnalyzerTranscriber.swift):接 macOS 26 的 `SpeechAnalyzer` / `SpeechTranscriber`。
2. **本機翻譯** — [`MLXTranslationService`](CaptionFlow/Translation/MLXTranslationService.swift):加入 `mlx-swift` SPM 套件,依 `ModelManager.effectiveModel(for:)` 載入 Qwen 並暖機常駐。
3. **Apple 翻譯** — [`AppleTranslationService`](CaptionFlow/Translation/AppleTranslationService.swift):接 Translation framework。
4. **音訊轉檔** — [`SystemAudioCaptureService`](CaptionFlow/Audio/SystemAudioCaptureService.swift):把 `CMSampleBuffer` 轉成 STT 需要的 16kHz mono。

## 模型自動推薦

[`HardwareProfile`](CaptionFlow/ModelManagement/HardwareProfiler.swift) 讀取實體記憶體,
預留 ~8GB(給 OS、STT、本 app、使用者同時開的軟體)後算出 LLM 預算;
[`ModelRecommender`](CaptionFlow/ModelManagement/ModelRecommender.swift) 在預算內挑品質最高的 Qwen。
使用者可在「設定 → 模型」關閉自動、手動指定;放不下的模型會標示「記憶體可能不足」。

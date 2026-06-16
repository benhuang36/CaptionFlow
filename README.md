# CaptionFlow

**English** | [繁體中文](README.zh-Hant.md)

Real-time, on-device captioning and translation for macOS. CaptionFlow captures
system audio, transcribes it to text, translates it, and shows the original plus
the translation as live subtitles — **everything runs locally**, with no cloud
service. The only network use is the one-time download of speech/translation
models.

- **Minimum OS**: macOS 26
- **Audio capture**: ScreenCaptureKit (requires Screen Recording permission)
- **Speech-to-text**: Apple SpeechAnalyzer / SpeechTranscriber, or WhisperKit (switchable)
- **Translation**: on-device LLM (MLX + Qwen, quality-first) or Apple Translation (low-latency fallback)
- **UI languages**: English (default), Traditional Chinese, Simplified Chinese, Japanese — follows the system language, with an in-app override

## How it works

```
ScreenCaptureKit ─► system audio
        │
        ▼
   STT (streaming) ──► partial source text (shown live)
        │ sentence finalized
        ▼
  Translation (LLM / Apple) ──► translated text
        │
        ▼
   SwiftUI display (bilingual / source only / translation only)
```

Incremental strategy: while a sentence is still being spoken, only the source
text updates live. Once the STT engine finalizes the sentence, it is sent for
translation, so you see "source appears instantly, translation follows a beat
later." The LLM translator also feeds the previous few lines as context and
automatically retries when an output comes back untranslated, which helps with
context-dependent short phrases and messy speech-to-text input.

## Features

- **Two STT engines** — Apple SpeechAnalyzer (native streaming, best integration)
  or WhisperKit (`base` / `small` / `large-v3`; often more robust for multilingual
  audio such as Japanese).
- **Two translation engines** — on-device LLM (MLX + Qwen, quality-first, default)
  or Apple Translation (lowest latency / lowest memory).
- **Memory-aware model recommendation** — picks the best Qwen model that fits your
  RAM budget, or lets you choose manually.
- **Built-in download manager** — download, cancel, and delete LLM and Whisper
  models from Settings.
- **History** — every Start → Stop is saved as a session you can review and copy.
- **Display modes** — bilingual, source only, or translation only.

## Requirements

- macOS 26
- Xcode 26, including the **Metal Toolchain** (needed to compile MLX):
  ```bash
  xcodebuild -downloadComponent MetalToolchain
  ```
- [XcodeGen](https://github.com/yonaskolb/XcodeGen):
  ```bash
  brew install xcodegen
  ```

## Build & run

The `.xcodeproj` is **not** committed — it is generated from `project.yml` with
XcodeGen. After cloning (or whenever you change `project.yml` / add files):

```bash
xcodegen generate
open CaptionFlow.xcodeproj
```

Then run from Xcode with **▶︎**. Running from Xcode is recommended: it handles
automatic signing, which the Screen Recording (TCC) permission is tied to.

> First run will prompt for Screen Recording permission. The first time you use a
> given STT/translation model, it is downloaded (a few GB) and cached locally for
> offline use afterwards.

## Configuration

Open **Settings** to choose:

- **STT engine** and (for WhisperKit) which model to use
- **Translation engine** (on-device LLM vs Apple Translation)
- **Model selection** — auto-recommend by memory, or pick manually
- **Language** — interface language (System default, English, 繁體中文, 简体中文, 日本語)

Source/target languages and the display mode are set from the control bar on the
main window.

## Project layout

| Directory | Contents |
|---|---|
| `App/` | App entry point |
| `Audio/` | ScreenCaptureKit capture, buffer conversion, level metering |
| `Speech/` | STT protocol + SpeechAnalyzer and WhisperKit transcribers |
| `Translation/` | Translation protocol + MLX/Qwen and Apple Translation services |
| `ModelManagement/` | Hardware profiling, model recommendation, download managers |
| `Pipeline/` | `CaptionPipeline` wiring the whole flow together |
| `Views/` | Main window, control bar, caption list, settings, history |
| `Models/` | `Language`, `DisplayMode`, `CaptionSegment`, `LLMModel`, history types |
| `Settings/` | `AppSettings` (UserDefaults), localization helper |
| `Resources/` | String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`) |
| `scripts/` | `package.sh` (build + sign + zip), `gen_xcstrings.py` (regenerate catalogs) |

## Privacy

All transcription and translation happen on-device. CaptionFlow does not send
audio or text to any server. The only outbound network request is downloading
models (from Hugging Face) on first use.

## License

[MIT](LICENSE)

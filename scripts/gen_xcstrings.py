#!/usr/bin/env python3
import json, os

# key(English) -> (zh-Hant, zh-Hans, ja)
T = {
    # SettingsView
    "General": ("一般", "常规", "一般"),
    "Translation Model": ("翻譯模型", "翻译模型", "翻訳モデル"),
    "Speech Recognition (STT)": ("語音辨識(STT)", "语音识别(STT)", "音声認識(STT)"),
    "Recognition Engine": ("辨識引擎", "识别引擎", "認識エンジン"),
    "Whisper Model": ("使用的 Whisper 模型", "使用的 Whisper 模型", "使用する Whisper モデル"),
    "Apple speech recognition streams natively with the best integration; for some languages WhisperKit may work better.":
        ("Apple 語音辨識為原生串流、整合最佳;部分語言可改用 WhisperKit。",
         "Apple 语音识别为原生流式、整合最佳;部分语言可改用 WhisperKit。",
         "Apple 音声認識はネイティブにストリーミングされ統合性が最も高く、一部の言語では WhisperKit が有効です。"),
    "Whisper Model Downloads": ("Whisper 模型下載", "Whisper 模型下载", "Whisper モデルのダウンロード"),
    "For multilingual audio (e.g. Japanese) Whisper is usually more reliable than Apple; large-v3 has the best quality but is larger and slower.":
        ("多語(如日文)通常比 Apple 更穩;large-v3 品質最佳但較大較慢。",
         "多语(如日语)通常比 Apple 更稳;large-v3 质量最佳但更大更慢。",
         "多言語(日本語など)では Apple より安定することが多く、large-v3 は最高品質ですが大きく低速です。"),
    "Translation": ("翻譯", "翻译", "翻訳"),
    "Translation Engine": ("翻譯引擎", "翻译引擎", "翻訳エンジン"),
    "Use the on-device LLM for best quality; switch to Apple Translation when memory is tight or you want the lowest latency.":
        ("品質優先時用本機 LLM;記憶體吃緊或想要最低延遲時可改用 Apple 翻譯。",
         "质量优先时用本地 LLM;内存吃紧或想要最低延迟时可改用 Apple 翻译。",
         "品質重視ならオンデバイス LLM を、メモリが厳しい/最小遅延が欲しい場合は Apple 翻訳を使います。"),
    "This Mac": ("這台機器", "这台机器", "この Mac"),
    "Physical Memory": ("實體記憶體", "物理内存", "物理メモリ"),
    "Available for LLM": ("可分配給 LLM", "可分配给 LLM", "LLM に割当可能"),
    "Recommended Model": ("建議模型", "建议模型", "推奨モデル"),
    "Model Selection": ("使用哪個模型", "使用哪个模型", "モデルの選択"),
    "Auto-recommend based on memory": ("依記憶體自動推薦", "依内存自动推荐", "メモリに応じて自動推奨"),
    "Manual selection": ("手動指定", "手动指定", "手動で指定"),
    "In use: %@": ("實際使用:%@", "实际使用:%@", "使用中:%@"),
    "may exceed memory": ("記憶體可能不足", "内存可能不足", "メモリ不足の可能性"),
    "Downloads": ("下載管理", "下载管理", "ダウンロード管理"),
    "Model files are stored in ~/Library/Caches; deleting one re-downloads it on next use.":
        ("模型檔存於 ~/Library/Caches;刪除後下次使用會重新下載。",
         "模型文件存于 ~/Library/Caches;删除后下次使用会重新下载。",
         "モデルは ~/Library/Caches に保存され、削除すると次回使用時に再ダウンロードされます。"),
    "Download": ("下載", "下载", "ダウンロード"),
    "Cancel download": ("取消下載", "取消下载", "ダウンロードを取消"),
    "Delete": ("刪除", "删除", "削除"),
    "Not downloaded": ("未下載", "未下载", "未ダウンロード"),
    "Not downloaded · %@": ("未下載 · %@", "未下载 · %@", "未ダウンロード · %@"),
    "Downloading…": ("下載中…", "下载中…", "ダウンロード中…"),
    "Downloaded · %@": ("已下載 · %@", "已下载 · %@", "ダウンロード済 · %@"),
    # ControlBar
    "Source": ("來源", "来源", "ソース"),
    "Target": ("目標", "目标", "翻訳先"),
    "Display": ("顯示", "显示", "表示"),
    "History": ("歷史記錄", "历史记录", "履歴"),
    "Audio Capture Test": ("音訊擷取測試", "音频采集测试", "音声キャプチャテスト"),
    "Preparing…": ("準備中…", "准备中…", "準備中…"),
    "Stop": ("停止", "停止", "停止"),
    "Start": ("開始", "开始", "開始"),
    # MainView
    "Translation: Apple Translation": ("翻譯:Apple 翻譯", "翻译:Apple 翻译", "翻訳:Apple 翻訳"),
    "Model: %@": ("翻譯模型:%@", "翻译模型:%@", "モデル:%@"),
    "Idle": ("閒置", "空闲", "待機"),
    # CaptionListView
    "Translating…": ("翻譯中…", "翻译中…", "翻訳中…"),
    "Press Start to show live captions": ("按「開始」即可顯示即時字幕", "按“开始”即可显示实时字幕", "「開始」を押すとライブ字幕が表示されます"),
    # HistoryView
    "No History Yet": ("尚無歷史記錄", "暂无历史记录", "履歴はまだありません"),
    "Each Start → Stop is saved as one entry.": ("每次「開始 → 停止」會存成一筆。", "每次“开始 → 停止”会存成一条。", "「開始 → 停止」ごとに 1 件として保存されます。"),
    "Delete Selected": ("刪除所選", "删除所选", "選択を削除"),
    "Clear All": ("清除全部", "清除全部", "すべて消去"),
    "Select an Entry": ("選擇一筆記錄", "选择一条记录", "項目を選択"),
    "Pick a session on the left to view the source and translation.":
        ("左側點一筆工作階段以檢視原文與譯文。", "左侧点一条会话以查看原文与译文。", "左側でセッションを選ぶと原文と訳文を表示します。"),
    "%@ → %@ · %@ lines": ("%@ → %@ · %@ 句", "%@ → %@ · %@ 句", "%@ → %@ · %@ 行"),
    "Copy All": ("複製全部", "复制全部", "すべてコピー"),
    "(no translation)": ("(無譯文)", "(无译文)", "(訳文なし)"),
    # DisplayMode
    "Bilingual": ("雙語", "双语", "バイリンガル"),
    "Source only": ("只顯示原文", "仅显示原文", "原文のみ"),
    "Translation only": ("只顯示譯文", "仅显示译文", "訳文のみ"),
    # STTEngine
    "Apple Speech": ("Apple 語音辨識", "Apple 语音识别", "Apple 音声認識"),
    # WhisperModelOption
    "base (fastest, basic quality)": ("base(最快、品質普通)", "base(最快、质量普通)", "base(最速・標準品質)"),
    "small (balanced, recommended)": ("small(平衡,推薦)", "small(平衡,推荐)", "small(バランス・推奨)"),
    "large-v3 (best quality, slower/larger)": ("large-v3(最佳品質、較慢/較大)", "large-v3(最佳质量、较慢/较大)", "large-v3(最高品質・低速/大容量)"),
    # TranslationEngine
    "On-device LLM (best quality)": ("本機 LLM(品質優先)", "本地 LLM(质量优先)", "オンデバイス LLM(品質重視)"),
    "Apple Translation (low latency)": ("Apple 翻譯(低延遲)", "Apple 翻译(低延迟)", "Apple 翻訳(低遅延)"),
    # Language
    "Auto Detect": ("自動偵測", "自动检测", "自動検出"),
    # AudioTestView
    "Buffers received": ("已收到緩衝", "已收到缓冲", "受信したバッファ"),
    "Start Capture": ("開始擷取", "开始采集", "キャプチャ開始"),
    "Close": ("關閉", "关闭", "閉じる"),
    # Pipeline status
    "Preparing translation model…": ("準備翻譯模型…", "准备翻译模型…", "翻訳モデルを準備中…"),
    "Starting transcription…": ("啟動轉錄…", "启动转录…", "文字起こしを開始中…"),
    "Audio stream interrupted: %@": ("音訊串流中斷:%@", "音频流中断:%@", "音声ストリームが中断:%@"),
    "Running": ("執行中", "运行中", "実行中"),
    "Failed to start: %@": ("啟動失敗:%@", "启动失败:%@", "起動に失敗:%@"),
    "Stopped": ("已停止", "已停止", "停止しました"),
    "Downloading Whisper model… %@": ("下載 Whisper 模型… %@", "下载 Whisper 模型… %@", "Whisper モデルをダウンロード中… %@"),
    "Downloading/loading model… %@": ("下載/載入模型中… %@", "下载/加载模型中… %@", "モデルをダウンロード/読込中… %@"),
    # AudioCaptureDiagnostic
    "Not started": ("尚未開始", "尚未开始", "未開始"),
    "Stream interrupted: %@": ("串流中斷:%@", "流中断:%@", "ストリームが中断:%@"),
    "Capturing — play any system audio and the meter below should move.":
        ("擷取中 — 播放任意系統聲音,下方音量條應會跳動。", "采集中 — 播放任意系统声音,下方音量条应会跳动。", "キャプチャ中 — 任意のシステム音を再生すると下のメーターが動きます。"),
    "Couldn't start: %@\nGrant access in System Settings → Privacy & Security → Screen Recording, then try again.":
        ("無法啟動:%@\n請到「系統設定 → 隱私權與安全性 → 螢幕錄製」授權後再試。",
         "无法启动:%@\n请到“系统设置 → 隐私与安全性 → 屏幕录制”授权后再试。",
         "起動できません:%@\n「システム設定 → プライバシーとセキュリティ → 画面収録」で許可してから再試行してください。"),
    "Stopped (received %@ audio buffers).": ("已停止(共收到 %@ 個音訊緩衝)。", "已停止(共收到 %@ 个音频缓冲)。", "停止しました(音声バッファを %@ 個受信)。"),
    # Errors
    "No capturable display found.": ("找不到可截取的顯示器。", "找不到可截取的显示器。", "キャプチャ可能なディスプレイが見つかりません。"),
    "Translation model not loaded yet.": ("翻譯模型尚未載入。", "翻译模型尚未加载。", "翻訳モデルがまだ読み込まれていません。"),
    "On-device transcription isn't supported for this language (%@) yet.":
        ("此語言(%@)尚不支援裝置端轉錄。", "此语言(%@)尚不支持设备端转录。", "この言語(%@)はまだオンデバイス文字起こしに対応していません。"),
    # Settings: language picker
    "Language": ("語言", "语言", "言語"),
    "System default": ("系統預設", "系统默认", "システムのデフォルト"),
    # Settings: locked while capturing
    "Stop capturing to change these settings.":
        ("停止擷取後才能變更這些設定。", "停止采集后才能更改这些设置。", "キャプチャを停止すると、これらの設定を変更できます。"),
}

LANGS = ["zh-Hant", "zh-Hans", "ja"]

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

strings = {}
for key, (hant, hans, ja) in T.items():
    locs = {"en": unit(key)}
    locs["zh-Hant"] = unit(hant)
    locs["zh-Hans"] = unit(hans)
    locs["ja"] = unit(ja)
    strings[key] = {"extractionState": "manual", "localizations": locs}

catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}

out_dir = "CaptionFlow/Resources"
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "Localizable.xcstrings"), "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")

# InfoPlist.xcstrings
info = {
    "NSMicrophoneUsageDescription": (
        "CaptionFlow needs access to system audio to generate captions in real time.",
        "CaptionFlow 需要存取系統音訊以即時產生字幕。",
        "CaptionFlow 需要访问系统音频以实时生成字幕。",
        "CaptionFlow は字幕をリアルタイムに生成するためシステム音声へのアクセスが必要です。"),
    "NSSpeechRecognitionUsageDescription": (
        "CaptionFlow transcribes speech to text on-device to generate captions.",
        "CaptionFlow 在裝置端將語音轉成文字以產生字幕。",
        "CaptionFlow 在设备端将语音转成文字以生成字幕。",
        "CaptionFlow は字幕生成のため音声をオンデバイスで文字に変換します。"),
}
info_strings = {}
for key, (en, hant, hans, ja) in info.items():
    info_strings[key] = {"extractionState": "manual", "localizations": {
        "en": unit(en), "zh-Hant": unit(hant), "zh-Hans": unit(hans), "ja": unit(ja)}}
info_catalog = {"sourceLanguage": "en", "strings": info_strings, "version": "1.0"}
with open(os.path.join(out_dir, "InfoPlist.xcstrings"), "w", encoding="utf-8") as f:
    json.dump(info_catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")

print(f"Wrote {len(strings)} UI strings + {len(info_strings)} InfoPlist strings.")

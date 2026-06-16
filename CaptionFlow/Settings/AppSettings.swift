import Foundation
import SwiftUI

/// 語音辨識引擎:Apple SpeechAnalyzer(原生串流、整合佳)或 WhisperKit(多語更穩)。
enum STTEngine: String, CaseIterable, Identifiable {
    case appleSpeech
    case whisperKit

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .whisperKit: return "WhisperKit"
        }
    }
}

/// WhisperKit 模型選項(名稱為 WhisperKit 可解析的關鍵字)。
enum WhisperModelOption: String, CaseIterable, Identifiable {
    case base
    case small
    case largeV3 = "large-v3"

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .base: return "base (fastest, basic quality)"
        case .small: return "small (balanced, recommended)"
        case .largeV3: return "large-v3 (best quality, slower/larger)"
        }
    }
}

/// 翻譯引擎:本機 LLM(品質優先,預設)或 Apple Translation(低延遲/低記憶體保底)。
enum TranslationEngine: String, CaseIterable, Identifiable {
    case localLLM
    case appleTranslation

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .localLLM: return "On-device LLM (best quality)"
        case .appleTranslation: return "Apple Translation (low latency)"
        }
    }
}

/// 使用者偏好,透過 UserDefaults 持久化。
@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("sourceLanguageCode") var sourceLanguageCode: String = "auto"
    @AppStorage("targetLanguageCode") var targetLanguageCode: String = "zh-Hant"
    @AppStorage("displayModeRaw") var displayModeRaw: String = DisplayMode.bilingual.rawValue
    // 品質優先:預設用本機 LLM(MLX + Qwen)。記憶體吃緊或想低延遲可在設定改 Apple 翻譯。
    @AppStorage("translationEngineRaw") var translationEngineRaw: String = TranslationEngine.localLLM.rawValue

    @AppStorage("autoSelectModel") var autoSelectModel: Bool = true
    @AppStorage("selectedModelID") var selectedModelID: String = ""

    @AppStorage("sttEngineRaw") var sttEngineRaw: String = STTEngine.appleSpeech.rawValue
    @AppStorage("whisperModelRaw") var whisperModelRaw: String = WhisperModelOption.small.rawValue

    /// 介面語言:"system" 跟隨系統,或語言碼(如 "ja")。預設跟隨系統,預設語言為英文。
    @AppStorage(appLanguageKey) var appLanguage: String = "system"

    /// 是否正在擷取/翻譯中(非持久化)。由 CaptionPipeline 在 start/stop 時鏡射其狀態,
    /// 讓獨立的 Settings scene(拿不到 pipeline)也能在執行中把「需重啟才生效」的
    /// 設定(STT/翻譯引擎、模型)變灰。pipeline 的設定是在 start() 當下快照的,
    /// 執行中改不會影響當前這場。
    @Published var isCapturing = false

    /// 套用到 SwiftUI environment 的 \.locale,即時切換所有 Text 的在地化。
    var locale: Locale {
        appLanguage == "system" ? .autoupdatingCurrent : Locale(identifier: appLanguage)
    }

    /// 介面語言選項(碼, 該語言自稱)。"system" 由 UI 另行顯示「系統預設」。
    static let appLanguageOptions: [(code: String, endonym: String)] = [
        ("system", ""),
        ("en", "English"),
        ("zh-Hant", "繁體中文"),
        ("zh-Hans", "简体中文"),
        ("ja", "日本語"),
    ]

    /// 變更介面語言。同步寫入 AppleLanguages,讓下次啟動也一致。
    func setAppLanguage(_ code: String) {
        appLanguage = code
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    var sourceLanguage: Language {
        get { Language.named(sourceLanguageCode) }
        set { sourceLanguageCode = newValue.code }
    }

    var targetLanguage: Language {
        get { Language.named(targetLanguageCode) }
        set { targetLanguageCode = newValue.code }
    }

    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: displayModeRaw) ?? .bilingual }
        set { displayModeRaw = newValue.rawValue }
    }

    var translationEngine: TranslationEngine {
        get { TranslationEngine(rawValue: translationEngineRaw) ?? .localLLM }
        set { translationEngineRaw = newValue.rawValue }
    }

    var sttEngine: STTEngine {
        get { STTEngine(rawValue: sttEngineRaw) ?? .appleSpeech }
        set { sttEngineRaw = newValue.rawValue }
    }

    var whisperModel: WhisperModelOption {
        get { WhisperModelOption(rawValue: whisperModelRaw) ?? .small }
        set { whisperModelRaw = newValue.rawValue }
    }
}

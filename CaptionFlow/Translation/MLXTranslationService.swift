import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// 本機 LLM(MLX + Qwen)翻譯。品質優先模式的主引擎。
/// 模型由 ModelManager.effectiveModel(for:) 決定(自動推薦或手動指定)。
///
/// 首次使用某模型會從 Hugging Face 下載權重(數 GB),之後快取於本機、離線可用。
final class MLXTranslationService: TranslationService {
    private let model: LLMModel
    private var container: ModelContainer?
    private var sourceName = ""
    private var targetName = ""
    private var targetCode = ""

    /// 載入進度(0...1),供 UI 顯示下載狀態。
    var onProgress: ((Double) -> Void)?

    init(model: LLMModel) {
        self.model = model
    }

    func prepare(source: Language, target: Language) async throws {
        sourceName = Self.languageName(source)
        targetName = Self.languageName(target)
        targetCode = target.code

        let handler = onProgress
        let container = try await LLMModelFactory.shared.loadContainer(
            hub: ModelStorage.hub,
            configuration: ModelConfiguration(id: model.id)
        ) { progress in
            handler?(progress.fractionCompleted)
        }
        self.container = container

        // 暖機:先跑一次短翻譯,讓 Metal kernel 編譯、模型常駐,避免首句卡頓。
        _ = try? await runTranslation("Hello.", context: [], container: container)
    }

    func translate(_ text: String, context: [TranslationContextLine]) async throws -> String {
        guard let container else {
            throw NSError(domain: "CaptionFlow", code: 201,
                          userInfo: [NSLocalizedDescriptionKey: Localized.string("Translation model not loaded yet.")])
        }
        return try await runTranslation(text, context: context, container: container)
    }

    func teardown() async {
        // 在 container 的 actor 內清快取,確保與推論互斥——不會在某個 eval 還在跑時
        // 清掉它的 GPU buffer(否則會觸發 Metal "Completed handler provided after commit" 斷言)。
        if let container {
            try? await container.perform { _ in
                MLX.GPU.clearCache()
            }
        }
        container = nil
    }

    // MARK: - 推論

    private func runTranslation(_ text: String,
                                context: [TranslationContextLine],
                                container: ModelContainer) async throws -> String {
        var parameters = GenerateParameters()
        parameters.temperature = 0.2
        parameters.maxTokens = 400

        // 每句獨立翻譯:用全新 ChatSession(空 KV cache),不累積前文。
        // 上下文改用 prompt 內文字提供(見 makePrompt),而非沿用 KV cache,
        // 這樣可控制「僅供參考、勿重譯」的邊界,也避免 cache 無限增長。
        let session = ChatSession(container, generateParameters: parameters)
        let prompt = Self.makePrompt(text: text, context: context,
                                     source: sourceName, target: targetName)
        let result = Self.cleanOutput(try await session.respond(to: prompt))

        // 小模型遇到破碎/亂的語音辨識,常退化成「整理原文」而非翻譯——
        // 輸出仍夾原文(日文假名)或英文單字。偵測到就用更強硬的 prompt、
        // temperature 0、不帶 context 重跑一次(全新 session,空 cache)。
        guard Self.looksUntranslated(result, target: targetCode) else { return result }

        var retryParams = GenerateParameters()
        retryParams.temperature = 0
        retryParams.maxTokens = 400
        let retrySession = ChatSession(container, generateParameters: retryParams)
        let retryPrompt = Self.makeRetryPrompt(text: text, source: sourceName, target: targetName)
        let retry = Self.cleanOutput(try await retrySession.respond(to: retryPrompt))
        // 重試仍失敗就回傳重試結果(已是最佳努力),不再無限重跑。
        return retry.isEmpty ? result : retry
    }

    private static func makePrompt(text: String,
                                   context: [TranslationContextLine],
                                   source: String, target: String) -> String {
        // 把前幾句「原文 → 譯文」當對話脈絡,讓模型理解語境依賴的短句。
        var contextBlock = ""
        if !context.isEmpty {
            let lines = context
                .map { "\($0.source) → \($0.translated)" }
                .joined(separator: "\n")
            contextBlock = """

            Preceding lines already translated (CONTEXT ONLY — do NOT translate or repeat these, use them only to understand what is being said):
            \(lines)

            """
        }

        return """
        You are a professional real-time subtitle translator. Translate the \(source) text below into \(target).

        Rules:
        - Output ONLY the \(target) translation of the LAST line — no explanations, no notes, no quotes, no original text, no context lines.
        - Write the output using ONLY \(target). It must contain NO words from any other language — not \(source), not English, nothing but \(target).
        - The input is raw speech-to-text: it may be fragmented, unpunctuated, run-on, or have repeated/filler words. Still TRANSLATE its meaning into \(target). Do NOT simply clean up, re-punctuate, or rephrase the original — you must convert it to \(target).
        - Translate every word, including names and proper nouns, into \(target) (transliterate into \(target) script if needed); never keep them in the original script.
        - Use the context to resolve meaning: greetings, set phrases and short utterances must be translated by their conversational meaning, not word-by-word literally.
        - Keep it natural and concise, suitable for a subtitle line.
        /no_think
        \(contextBlock)
        Translate this line:
        \(text)
        """
    }

    /// 重試用的強硬 prompt:不帶 context,只逼模型把整段轉成目標語言。
    private static func makeRetryPrompt(text: String, source: String, target: String) -> String {
        """
        The text below is in \(source). Output ONLY its \(target) translation — nothing else.
        Do NOT copy, echo, or re-punctuate the \(source). Every single character of your answer MUST be \(target).
        If the text is broken or fragmented, translate its meaning as best you can, still entirely in \(target).
        /no_think

        \(text)
        """
    }

    /// 判斷輸出是否「其實沒翻成目標語言」。
    /// - 目標非日文卻含平假名/片假名 → 假名只屬日文,鐵定殘留原文。
    /// - 目標為 CJK 卻夾拉丁字母單字(≥2 連續字母)→ 混入英文/未轉寫。
    private static func looksUntranslated(_ output: String, target: String) -> Bool {
        if output.isEmpty { return false }

        if target != "ja", output.unicodeScalars.contains(where: isKana) {
            return true
        }

        let cjkTargets: Set<String> = ["zh-Hant", "zh-Hans", "ja", "ko"]
        if cjkTargets.contains(target) {
            var run = 0
            for scalar in output.unicodeScalars {
                let v = scalar.value
                let isLatinLetter = (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
                if isLatinLetter {
                    run += 1
                    if run >= 2 { return true }   // 連續 2 個拉丁字母即視為夾了外語單字
                } else {
                    run = 0
                }
            }
        }
        return false
    }

    /// 平假名(ぁ-ゟ)或片假名(゠-ヿ)。
    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (v >= 0x3041 && v <= 0x309F) || (v >= 0x30A0 && v <= 0x30FF)
    }

    /// 清掉 Qwen3 可能輸出的 <think>…</think> 推理段與多餘空白。
    private static func cleanOutput(_ raw: String) -> String {
        var text = raw
        if let end = text.range(of: "</think>") {
            text = String(text[end.upperBound...])
        }
        text = text.replacingOccurrences(of: "<think>", with: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func languageName(_ language: Language) -> String {
        if language.isAuto { return "the source language" }
        switch language.code {
        case "zh-Hant": return "Traditional Chinese"
        case "zh-Hans": return "Simplified Chinese"
        case "en": return "English"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        default: return language.displayName
        }
    }
}

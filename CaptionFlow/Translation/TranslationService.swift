import Foundation

/// 一句先前已翻好的字幕,作為後續句子的翻譯上下文。
/// 讓 LLM 知道對話脈絡,避免把有語境依賴的短句照字面拆譯
/// (例:「ただいま」依前文是「我回來了」,而非字面的「剛剛/現在」)。
struct TranslationContextLine {
    let source: String
    let translated: String
}

/// 翻譯服務抽象介面。prepare() 在開始前載入/暖機模型;
/// translate() 對「已 finalize 的整句」做翻譯。
///
/// context 為緊接在前、已翻好的句子(由舊到新),供有上下文能力的引擎參考;
/// 句級 MT(如 Apple Translation)可忽略。
protocol TranslationService: AnyObject {
    func prepare(source: Language, target: Language) async throws
    func translate(_ text: String, context: [TranslationContextLine]) async throws -> String
    func teardown() async
}

extension TranslationService {
    /// 無上下文的便利呼叫(暖機、測試用)。
    func translate(_ text: String) async throws -> String {
        try await translate(text, context: [])
    }
}

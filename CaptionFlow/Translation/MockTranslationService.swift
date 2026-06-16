import Foundation

/// 假翻譯器,讓骨架不需載入模型也能展示「原文 + 譯文」流程。
/// 加一點延遲來模擬 LLM 推論時間。
final class MockTranslationService: TranslationService {
    func prepare(source: Language, target: Language) async throws {}

    func translate(_ text: String, context: [TranslationContextLine]) async throws -> String {
        try? await Task.sleep(nanoseconds: 600_000_000)
        return "【譯】" + text
    }

    func teardown() async {}
}

import Foundation

/// Apple Translation framework 翻譯服務。低延遲 / 低記憶體,免下載大模型。
/// 實際工作交給 AppleTranslationBridge(配合 AppleTranslationHost 的 TranslationSession)。
final class AppleTranslationService: TranslationService {
    private let bridge: AppleTranslationBridge

    init(bridge: AppleTranslationBridge) {
        self.bridge = bridge
    }

    func prepare(source: Language, target: Language) async throws {
        await bridge.configure(source: source, target: target)
    }

    // Apple Translation 為句級 MT,無法吃對話上下文,忽略 context。
    func translate(_ text: String, context: [TranslationContextLine]) async throws -> String {
        try await bridge.translate(text)
    }

    func teardown() async {}
}

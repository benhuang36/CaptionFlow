import Foundation
import Translation
import Combine

/// 橋接 Apple Translation。`TranslationSession` 只能由 SwiftUI 的 `.translationTask`
/// 取得(見 AppleTranslationHost),所以這裡用一條請求佇列把 session 跟 pipeline 的
/// 命令式呼叫接起來:pipeline 丟文字進來 → host 內的 session 翻好 → 回傳結果。
@MainActor
final class AppleTranslationBridge: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private struct Request {
        let text: String
        let continuation: CheckedContinuation<String, Error>
    }

    private let requests: AsyncStream<Request>
    private let submit: AsyncStream<Request>.Continuation

    init() {
        var continuation: AsyncStream<Request>.Continuation!
        requests = AsyncStream { continuation = $0 }
        submit = continuation
    }

    /// 設定來源/目標語言;會觸發 host 的 translationTask(語言對改變時)。
    func configure(source: Language, target: Language) {
        configuration = TranslationSession.Configuration(
            source: source.isAuto ? nil : Locale.Language(identifier: source.code),
            target: Locale.Language(identifier: target.code)
        )
    }

    func translate(_ text: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            submit.yield(Request(text: text, continuation: continuation))
        }
    }

    /// 由 AppleTranslationHost 在 `.translationTask` 內呼叫,持續處理佇列直到被取消。
    func process(using session: TranslationSession) async {
        for await request in requests {
            do {
                let response = try await session.translate(request.text)
                request.continuation.resume(returning: response.targetText)
            } catch {
                request.continuation.resume(throwing: error)
            }
        }
    }
}

import Foundation

/// 透過使用者自訂的 OpenAI 相容 endpoint(/chat/completions)翻譯。
/// 讓使用者用雲端或自架的較強模型,繞過本機 LLM 的記憶體與速度限制。
///
/// ⚠️ 隱私:這會把(轉錄出的)文字送到該 endpoint,**不是全本機**。
/// 支援任何 OpenAI 相容服務:OpenAI / OpenRouter / Groq / Together,
/// 以及本機的 Ollama / LM Studio / llama.cpp(都有 OpenAI 相容層)。
final class RemoteTranslationService: TranslationService {
    private let endpointText: String
    private let apiKey: String
    private let model: String

    private var endpoint: URL?
    private var sourceName = ""
    private var targetName = ""

    init(endpoint: String, apiKey: String, model: String) {
        self.endpointText = endpoint
        self.apiKey = apiKey
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prepare(source: Language, target: Language) async throws {
        sourceName = Self.languageName(source)
        targetName = Self.languageName(target)
        guard let url = Self.resolveURL(endpointText) else {
            throw NSError(domain: "CaptionFlow", code: 301,
                          userInfo: [NSLocalizedDescriptionKey: Localized.string("Invalid custom endpoint URL.")])
        }
        endpoint = url
    }

    func translate(_ text: String, context: [TranslationContextLine]) async throws -> String {
        guard let endpoint else {
            throw NSError(domain: "CaptionFlow", code: 302,
                          userInfo: [NSLocalizedDescriptionKey: Localized.string("Invalid custom endpoint URL.")])
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "stream": false,
            "messages": Self.messages(text: text, context: context,
                                      source: sourceName, target: targetName),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CaptionFlow", code: 303,
                          userInfo: [NSLocalizedDescriptionKey: Localized.string("Custom endpoint returned no response.")])
        }
        guard (200..<300).contains(http.statusCode) else {
            let code = String(http.statusCode)
            let detail = String(String(data: data, encoding: .utf8)?.prefix(200) ?? "")
            throw NSError(domain: "CaptionFlow", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey:
                            Localized.string("Custom endpoint error \(code): \(detail)")])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "CaptionFlow", code: 304,
                          userInfo: [NSLocalizedDescriptionKey: Localized.string("Unexpected response from custom endpoint.")])
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func teardown() async {}

    // MARK: - 請求組裝

    /// 接受完整 URL 或 base URL;沒有 /chat/completions 路徑就補上(對使用者寬容)。
    private static func resolveURL(_ raw: String) -> URL? {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        if !str.lowercased().contains("/chat/completions") {
            if str.hasSuffix("/") { str.removeLast() }
            str += "/chat/completions"
        }
        return URL(string: str)
    }

    private static func messages(text: String, context: [TranslationContextLine],
                                 source: String, target: String) -> [[String: String]] {
        let system = """
        You are a professional real-time subtitle translator. Translate from \(source) into \(target).
        Output ONLY the \(target) translation of the user's line — nothing else: no notes, no quotes, \
        no original text, no other language. Render greetings and short phrases by their conversational \
        meaning, not word-by-word. Keep it natural and concise, suitable for a subtitle line.
        """

        var userContent = ""
        if !context.isEmpty {
            let lines = context.map { "\($0.source) → \($0.translated)" }.joined(separator: "\n")
            userContent += "Earlier lines for context (do NOT translate or repeat these):\n\(lines)\n\n"
        }
        userContent += "Translate this line:\n\(text)"

        return [
            ["role": "system", "content": system],
            ["role": "user", "content": userContent],
        ]
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

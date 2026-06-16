import Foundation
import Combine

/// 歷史儲存:每次「開始 → 結束」為一筆工作階段(HistorySession)。
/// 持久化為 JSON,存於 Application Support/CaptionFlow/history.json。
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var sessions: [HistorySession] = []

    private var currentSessionID: UUID?
    private let fileURL: URL

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "CaptionFlow", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "history.json")
        load()
    }

    /// 開始一筆新的工作階段。
    func beginSession(source: Language, target: Language) {
        // 若上一筆還沒收尾(例外情況),先結算。
        endSession()
        let session = HistorySession(sourceLanguageCode: source.code,
                                     targetLanguageCode: target.code)
        sessions.append(session)
        currentSessionID = session.id
        save()
    }

    /// 把一句原文+譯文加入目前工作階段。
    func appendLine(sourceText: String, translatedText: String) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let id = currentSessionID,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].lines.append(
            HistoryLine(sourceText: trimmed,
                        translatedText: translatedText.trimmingCharacters(in: .whitespacesAndNewlines)))
        save()
    }

    /// 結束目前工作階段。沒有任何內容的階段不予保留。
    func endSession() {
        guard let id = currentSessionID,
              let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[index].lines.isEmpty {
            sessions.remove(at: index)
        } else {
            sessions[index].endDate = .now
        }
        currentSessionID = nil
        save()
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        sessions.removeAll { ids.contains($0.id) }
        if let current = currentSessionID, !sessions.contains(where: { $0.id == current }) {
            currentSessionID = nil
        }
        save()
    }

    func delete(_ session: HistorySession) {
        delete(ids: [session.id])
    }

    func clearAll() {
        sessions.removeAll()
        currentSessionID = nil
        save()
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistorySession].self, from: data) else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

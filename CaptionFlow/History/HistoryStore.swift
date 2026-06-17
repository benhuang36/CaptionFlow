import Foundation
import Combine

/// 歷史儲存:每次「開始 → 結束」為一筆工作階段(HistorySession)。
/// 持久化為 JSON,存於 Application Support/CaptionFlow/history.json。
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var sessions: [HistorySession] = []

    private var currentSessionID: UUID?
    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?

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
        scheduleSave(debounced: false)
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
        // 高頻路徑:去抖動 + 背景寫檔,避免每句都在主執行緒重編碼整包(跑久了會卡 UI)。
        scheduleSave(debounced: true)
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
        scheduleSave(debounced: false)
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        sessions.removeAll { ids.contains($0.id) }
        if let current = currentSessionID, !sessions.contains(where: { $0.id == current }) {
            currentSessionID = nil
        }
        scheduleSave(debounced: false)
    }

    func delete(_ session: HistorySession) {
        delete(ids: [session.id])
    }

    func clearAll() {
        sessions.removeAll()
        currentSessionID = nil
        scheduleSave(debounced: false)
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistorySession].self, from: data) else { return }
        sessions = decoded
    }

    /// 排程一次寫檔。編碼+寫檔都在背景執行緒(detached),不卡主執行緒。
    /// debounced=true(高頻的逐句路徑):延遲 2 秒並覆蓋前一個未完成的排程,
    /// 把連續多句合併成一次寫入。debounced=false(begin/end/delete 等低頻結構變更):立即寫。
    /// 取一份 sessions 快照(值型別,COW),交給背景 task,避免跨執行緒共享可變狀態。
    private func scheduleSave(debounced: Bool) {
        pendingSave?.cancel()
        let snapshot = sessions
        let url = fileURL
        pendingSave = Task.detached(priority: .utility) {
            if debounced {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
            }
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

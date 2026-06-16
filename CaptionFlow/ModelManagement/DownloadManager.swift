import Foundation
import Combine

/// 通用的模型下載管理:追蹤狀態、可下載 / 取消 / 刪除。
/// 實際的「是否已下載 / 大小 / 下載 / 刪除」由注入的閉包決定,
/// 因此同一套邏輯可用於 LLM 與 Whisper(見下方兩個子類別)。
@MainActor
class DownloadManager: ObservableObject {
    enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case downloaded(sizeBytes: Int64)
    }

    @Published private(set) var statuses: [String: Status] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    private let isDownloadedFn: (String) -> Bool
    private let sizeFn: (String) -> Int64
    private let downloadFn: (String, @escaping (Double) -> Void) async throws -> Void
    private let deleteFn: (String) throws -> Void

    init(isDownloaded: @escaping (String) -> Bool,
         size: @escaping (String) -> Int64,
         download: @escaping (String, @escaping (Double) -> Void) async throws -> Void,
         delete: @escaping (String) throws -> Void) {
        self.isDownloadedFn = isDownloaded
        self.sizeFn = size
        self.downloadFn = download
        self.deleteFn = delete
    }

    func status(forKey key: String) -> Status {
        statuses[key] ?? .notDownloaded
    }

    /// 重新掃描磁碟更新狀態(下載中的不動)。
    func refresh(keys: [String]) {
        for key in keys {
            if case .downloading = statuses[key] { continue }
            statuses[key] = resolvedStatus(key)
        }
    }

    func download(key: String) {
        guard tasks[key] == nil else { return }
        statuses[key] = .downloading(0)
        tasks[key] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.downloadFn(key) { fraction in
                    Task { @MainActor in
                        if case .downloading = self.statuses[key] {
                            self.statuses[key] = .downloading(fraction)
                        }
                    }
                }
            } catch {
                if error is CancellationError || Task.isCancelled {
                    try? self.deleteFn(key)   // 取消時清掉部分下載
                }
            }
            self.statuses[key] = self.resolvedStatus(key)
            self.tasks[key] = nil
        }
    }

    func cancel(key: String) {
        tasks[key]?.cancel()
    }

    func delete(key: String) {
        try? deleteFn(key)
        statuses[key] = .notDownloaded
    }

    private func resolvedStatus(_ key: String) -> Status {
        isDownloadedFn(key) ? .downloaded(sizeBytes: sizeFn(key)) : .notDownloaded
    }
}

/// 本機 LLM 的下載管理。
@MainActor
final class LLMDownloadManager: DownloadManager {}

/// WhisperKit 模型的下載管理。
@MainActor
final class WhisperDownloadManager: DownloadManager {}

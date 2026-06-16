import Foundation
import Hub

/// 本機 LLM 模型檔的存放與管理。與 MLX 載入用同一個 HubApi(下載到 Caches 目錄),
/// 確保「列出/下載/刪除」與「實際載入」看到的是同一份檔案。
enum ModelStorage {
    /// 與 MLXLMCommon 的 defaultHubApi 相同:下載基底為 Caches 目錄。
    static let downloadBase: URL =
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!

    static let hub = HubApi(downloadBase: downloadBase)

    static func location(repoId: String) -> URL {
        hub.localRepoLocation(Hub.Repo(id: repoId))
    }

    static func isDownloaded(repoId: String) -> Bool {
        FileManager.default.fileExists(
            atPath: location(repoId: repoId).appending(path: "config.json").path)
    }

    static func sizeOnDisk(repoId: String) -> Int64 {
        directorySize(location(repoId: repoId))
    }

    static func delete(repoId: String) throws {
        let directory = location(repoId: repoId)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    static func download(repoId: String, progress: @escaping (Double) -> Void) async throws {
        _ = try await hub.snapshot(
            from: Hub.Repo(id: repoId),
            matching: ["*.safetensors", "*.json", "*.txt", "*.model", "tokenizer*"]
        ) { p in
            progress(p.fractionCompleted)
        }
    }
}

/// 計算目錄內所有檔案總大小(bytes)。
func directorySize(_ directory: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total: Int64 = 0
    for case let url as URL in enumerator {
        total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    return total
}

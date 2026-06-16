import Foundation
import WhisperKit

/// WhisperKit 模型檔的存放與管理。下載基底固定在 App Support,讓「下載/刪除/載入」一致。
enum WhisperModelStorage {
    static let downloadBase: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "CaptionFlow/WhisperModels", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static let repoPath = "models/argmaxinc/whisperkit-coreml"

    /// variant 為 WhisperModelOption.rawValue(base / small / large-v3)。
    static func folder(variant: String) -> URL {
        downloadBase
            .appending(path: repoPath, directoryHint: .isDirectory)
            .appending(path: "openai_whisper-\(variant)", directoryHint: .isDirectory)
    }

    static func isDownloaded(variant: String) -> Bool {
        let directory = folder(variant: variant)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        return !contents.isEmpty
    }

    static func sizeOnDisk(variant: String) -> Int64 {
        directorySize(folder(variant: variant))
    }

    static func delete(variant: String) throws {
        let directory = folder(variant: variant)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    static func download(variant: String, progress: @escaping (Double) -> Void) async throws {
        _ = try await WhisperKit.download(variant: variant, downloadBase: downloadBase) { p in
            progress(p.fractionCompleted)
        }
    }
}

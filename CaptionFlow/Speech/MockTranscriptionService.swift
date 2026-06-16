import Foundation
import CoreMedia

/// 不需要音訊或權限的假轉錄器,讓骨架可以直接跑起來看 UI。
/// 會逐字吐出 partial、句末送出 final,模擬真實串流行為。
final class MockTranscriptionService: TranscriptionService {
    var onUpdate: ((TranscriptUpdate) -> Void)?

    private var task: Task<Void, Never>?

    private let script = [
        "Hello everyone, thanks for joining today's meeting.",
        "Let's start with a quick recap of last week's progress.",
        "The new captioning feature is almost ready for testing.",
        "Please share any feedback you have by the end of the day.",
    ]

    func start(sourceLanguage: Language) async throws {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                for line in self.script {
                    if Task.isCancelled { return }
                    await self.emit(line)
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
            }
        }
    }

    /// 逐字吐 partial,最後送 final。
    private func emit(_ line: String) async {
        let words = line.split(separator: " ").map(String.init)
        var current = ""
        for word in words {
            if Task.isCancelled { return }
            current += (current.isEmpty ? "" : " ") + word
            onUpdate?(TranscriptUpdate(text: current, isFinal: false))
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
        onUpdate?(TranscriptUpdate(text: line, isFinal: true))
    }

    func append(_ sampleBuffer: CMSampleBuffer) { /* mock 不需要音訊 */ }

    func stop() async {
        task?.cancel()
        task = nil
    }
}

import Foundation
import CoreMedia

/// 一次轉錄更新。partial(isFinal == false)會持續更新同一句;
/// final 代表這句話定稿,可以送去翻譯。
struct TranscriptUpdate {
    let text: String
    let isFinal: Bool
}

/// 串流語音轉文字的抽象介面。
protocol TranscriptionService: AnyObject {
    var onUpdate: ((TranscriptUpdate) -> Void)? { get set }

    func start(sourceLanguage: Language) async throws
    /// 餵入截取到的系統音訊。
    func append(_ sampleBuffer: CMSampleBuffer)
    func stop() async
}

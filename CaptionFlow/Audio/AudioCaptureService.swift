import Foundation
import CoreMedia

/// 系統音訊截取的抽象介面。實作會把音訊以 CMSampleBuffer 串流出來,
/// 餵給 STT。下游負責轉成 16kHz mono 的格式。
protocol AudioCaptureService: AnyObject {
    var onAudio: ((CMSampleBuffer) -> Void)? { get set }
    func start() async throws
    func stop() async
}

import Foundation
import CoreMedia
import ScreenCaptureKit

/// 用 ScreenCaptureKit 截取系統音訊。需要「螢幕錄製」權限(即使只取音訊)。
///
/// 注意:第一次 start() 會觸發 TCC 權限提示。骨架階段 CaptionPipeline 預設走 mock,
/// 不會呼叫這裡;把 pipeline 的 useMockServices 設為 false 後才會真的啟動。
final class SystemAudioCaptureService: NSObject, AudioCaptureService, SCStreamOutput, SCStreamDelegate {
    var onAudio: ((CMSampleBuffer) -> Void)?
    /// 串流中途出錯(例如使用者撤銷權限)會透過這裡回報。
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private let sampleQueue = DispatchQueue(label: "com.captionflow.audio.sck")

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "CaptionFlow", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: Localized.string("No capturable display found.")])
        }

        let filter = SCContentFilter(display: display,
                                     excludingApplications: [],
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 16_000      // 直接以 STT 想要的取樣率擷取
        config.channelCount = 1
        config.excludesCurrentProcessAudio = true
        // SCStream 仍需有效的視訊設定,給最小尺寸即可(我們只用音訊)。
        config.width = 2
        config.height = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        onAudio?(sampleBuffer)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }
}

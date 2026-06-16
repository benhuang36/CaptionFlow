import Foundation
import CoreMedia
import ScreenCaptureKit

/// 用 ScreenCaptureKit 截取系統音訊。需要「螢幕錄製」權限(即使只取音訊)。
/// 第一次 start() 會觸發 TCC 權限提示。
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
        // 我們不用視訊,把更新降到最低(1fps),減少產生又丟棄的 frame。
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        // 也註冊 .screen 輸出來「接住」視訊 frame 並默默丟棄(見下方 handler 的 guard)。
        // 否則 SCStream 仍會產生視訊 frame、卻找不到接收者,瘋狂洗版
        // "stream output NOT found. Dropping frame"。
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
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

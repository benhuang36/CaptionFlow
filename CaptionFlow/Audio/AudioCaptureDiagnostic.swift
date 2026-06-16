import Foundation
import Combine

/// 音訊擷取自我檢測:啟動 ScreenCaptureKit,把收到的緩衝換算成音量,
/// 讓使用者用「播放聲音 → 音量條跳動」直接確認系統音訊有抓到。
@MainActor
final class AudioCaptureDiagnostic: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var level: Float = 0      // 0...1,給音量條
    @Published private(set) var peak: Float = 0
    @Published private(set) var bufferCount = 0
    @Published private(set) var status = Localized.string("Not started")

    private let service = SystemAudioCaptureService()

    func start() async {
        bufferCount = 0
        peak = 0

        service.onAudio = { [weak self] buffer in
            let rms = AudioLevelMeter.rms(from: buffer)
            let normalized = AudioLevelMeter.normalized(rms: rms)
            Task { @MainActor in self?.ingest(normalized) }
        }
        service.onError = { [weak self] error in
            Task { @MainActor in
                self?.isRunning = false
                self?.status = Localized.string("Stream interrupted: \(error.localizedDescription)")
            }
        }

        do {
            try await service.start()
            isRunning = true
            status = Localized.string("Capturing — play any system audio and the meter below should move.")
        } catch {
            isRunning = false
            status = Localized.string("Couldn't start: \(error.localizedDescription)\nGrant access in System Settings → Privacy & Security → Screen Recording, then try again.")
        }
    }

    func stop() async {
        await service.stop()
        isRunning = false
        level = 0
        let n = "\(bufferCount)"
        status = Localized.string("Stopped (received \(n) audio buffers).")
    }

    private func ingest(_ normalized: Float) {
        bufferCount += 1
        level = normalized
        peak = max(peak * 0.95, normalized)
    }
}

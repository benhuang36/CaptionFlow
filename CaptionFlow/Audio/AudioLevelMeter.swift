import Foundation
import CoreMedia

/// 從 ScreenCaptureKit 的音訊 CMSampleBuffer 算出 RMS 音量。
/// SCK 預設以 Float32 線性 PCM 輸出,這裡據此解讀。
enum AudioLevelMeter {
    /// 回傳這個緩衝的 RMS(約 0...1)。無資料時回 0。
    static func rms(from sampleBuffer: CMSampleBuffer) -> Float {
        var sumOfSquares: Float = 0
        var sampleCount = 0

        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            for buffer in audioBufferList {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.assumingMemoryBound(to: Float.self)
                for i in 0..<count {
                    let value = samples[i]
                    sumOfSquares += value * value
                }
                sampleCount += count
            }
        }

        guard sampleCount > 0 else { return 0 }
        return (sumOfSquares / Float(sampleCount)).squareRoot()
    }

    /// 把 RMS 轉成適合音量條的 0...1 值(-60dB ... 0dB 線性映射)。
    static func normalized(rms: Float) -> Float {
        let db = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (db + 60) / 60))
    }

    /// 取出緩衝的原始 Float 樣本(SCK 為 16kHz mono Float32,可直接餵 WhisperKit)。
    static func samples(from sampleBuffer: CMSampleBuffer) -> [Float] {
        var output: [Float] = []
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            for buffer in audioBufferList {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let pointer = data.assumingMemoryBound(to: Float.self)
                output.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
            }
        }
        return output
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }
}

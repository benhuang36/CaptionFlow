import Foundation
import AVFoundation
import CoreMedia

enum AudioBufferError: Error {
    case noFormatDescription
    case cannotCreateBuffer
    case conversionFailed(NSError?)
}

/// 把 ScreenCaptureKit 的 CMSampleBuffer 轉成 AVAudioPCMBuffer。
enum PCMBufferFactory {
    static func make(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = sampleBuffer.formatDescription,
              var asbd = formatDescription.audioStreamBasicDescription else {
            throw AudioBufferError.noFormatDescription
        }
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw AudioBufferError.cannotCreateBuffer
        }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioBufferError.cannotCreateBuffer
        }
        buffer.frameLength = frameCount

        try sampleBuffer.copyPCMData(fromRange: 0..<sampleBuffer.numSamples,
                                     into: buffer.mutableAudioBufferList)
        return buffer
    }
}

/// 將輸入緩衝轉成目標(analyzer)格式。內部重用 AVAudioConverter。
/// 由單一序列佇列呼叫,非執行緒安全。
final class BufferConverter {
    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none // 即時用途:犧牲一點品質換低延遲
        }
        guard let converter else { throw AudioBufferError.conversionFailed(nil) }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw AudioBufferError.cannotCreateBuffer
        }

        var nsError: NSError?
        var consumed = false
        let status = converter.convert(to: output, error: &nsError) { _, inputStatus in
            defer { consumed = true }
            inputStatus.pointee = consumed ? .noDataNow : .haveData
            return consumed ? nil : buffer
        }

        if status == .error { throw AudioBufferError.conversionFailed(nsError) }
        return output
    }
}

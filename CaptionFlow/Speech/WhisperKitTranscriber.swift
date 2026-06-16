import Foundation
import CoreMedia
import AVFoundation
import WhisperKit

/// 用 WhisperKit(Core ML / ANE)做語音轉文字。Whisper 非原生串流,
/// 這裡自行做「滑動視窗 + 靜音斷句」:
///   - 持續累積目前語句的音訊樣本
///   - 偵測到一段尾端靜音(或語句過長)就定稿並清空,開始下一句
///   - 語句進行中,間隔重新轉錄整段以更新 partial(逐步顯示)
final class WhisperKitTranscriber: TranscriptionService {
    var onUpdate: ((TranscriptUpdate) -> Void)?

    private let modelName: String
    private var whisperKit: WhisperKit?
    private var languageCode: String?      // Whisper 語言碼,nil = 自動偵測

    /// 模型下載進度(0...1),供 UI 顯示。
    var onProgress: ((Double) -> Void)?

    // 緩衝(append 來自 SCK 佇列、loop 在另一條 Task,以 lock 保護)
    private let lock = NSLock()
    private var segment: [Float] = []
    private var hasSpeech = false
    private var trailingSilenceSamples = 0

    private var loop: Task<Void, Never>?
    private var lastTranscribeAt = Date.distantPast
    private var lastEmittedFinal = ""

    // Whisper 需要 16kHz mono Float;SCK 實際輸出常為 48kHz,故統一重採樣。
    private let converter = BufferConverter()
    private let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private let sampleRate = 16_000
    private let silenceRMS: Float = 0.005        // 低於此視為靜音(系統音量可能偏低,訂寬鬆些)
    private let minPartialSeconds = 0.5          // 語句至少這麼長才開始轉
    private let transcribeInterval = 0.45        // 兩次轉錄的最小間隔(秒)
    // 斷句策略:句尾有結束標點 + 短停頓就斷;否則靠停頓長度斷。
    // 口語日文 Whisper 幾乎不打標點,故另加「軟斷句」:夠長 + 任何小停頓就斷,
    // 避免連續語流(無標點)一路衝到上限變成一面牆。
    private let sentenceEndSilence = 0.5         // 已成句(有結束標點)+ 這麼久停頓 → 定稿
    private let hardSilence = 1.0                // 不論是否成句,停這麼久就定稿(說話者停下)
    private let softBreakSeconds = 6.0           // 語句已達這麼長 + 換氣小停頓 → 軟斷句(不必有標點)
    private let softBreakSilence = 0.4           // 軟斷句所需的最短停頓(一次換氣)
    private let maxSegmentSeconds = 9.0          // 語句過長就強制定稿(安全上限)
    private let terminators: Set<Character> = [".", "?", "!", "。", "?", "!", "…"]

    init(model: String) {
        self.modelName = model
    }

    func start(sourceLanguage: Language) async throws {
        languageCode = sourceLanguage.isAuto
            ? nil
            : Locale(identifier: sourceLanguage.code).language.languageCode?.identifier

        // 先下載(回報進度),再從本機資料夾載入,避免 init 內靜默下載看起來像卡住。
        // 下載基底與 WhisperModelStorage 一致,設定裡才管理得到。
        let handler = onProgress
        let folder = try await WhisperKit.download(
            variant: modelName, downloadBase: WhisperModelStorage.downloadBase
        ) { progress in
            handler?(progress.fractionCompleted)
        }
        whisperKit = try await WhisperKit(
            WhisperKitConfig(model: modelName,
                             downloadBase: WhisperModelStorage.downloadBase,
                             modelFolder: folder.path))
        startLoop()
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard let pcm = try? PCMBufferFactory.make(from: sampleBuffer),
              let converted = try? converter.convert(pcm, to: whisperFormat) else { return }
        let floats = Self.floatArray(from: converted)
        guard !floats.isEmpty else { return }
        let rms = AudioLevelMeter.rms(floats)
        lock.lock()
        segment.append(contentsOf: floats)
        if rms > silenceRMS {
            hasSpeech = true
            trailingSilenceSamples = 0
        } else {
            trailingSilenceSamples += floats.count
        }
        lock.unlock()
    }

    func stop() async {
        loop?.cancel()
        loop = nil
        // 收尾:把剩下的語句定稿。
        let (samples, speech) = drain()
        if speech, let text = try? await transcribe(samples) {
            emitFinal(text)
        }
        whisperKit = nil
    }

    // MARK: - 處理迴圈

    private func startLoop() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { break }
                await self?.tick()
            }
        }
    }

    private func tick() async {
        lock.lock()
        let count = segment.count
        let speech = hasSpeech
        let silence = Double(trailingSilenceSamples) / Double(sampleRate)
        lock.unlock()

        let seconds = Double(count) / Double(sampleRate)
        guard speech, seconds >= minPartialSeconds else { return }
        guard Date().timeIntervalSince(lastTranscribeAt) >= transcribeInterval else { return }

        lock.lock()
        let snapshot = segment
        lock.unlock()

        lastTranscribeAt = Date()
        let text = (try? await transcribe(snapshot)) ?? ""
        guard !text.isEmpty else { return }

        // 定稿條件(任一):
        //  - 過長(安全上限)
        //  - 停頓很久(說話者停下)
        //  - 已成句(有結束標點)+ 短停頓
        //  - 軟斷句:夠長 + 一次換氣的小停頓(處理無標點的連續日文語流)
        let endsSentence = endsWithTerminator(text)
        let finalize = seconds >= maxSegmentSeconds
            || silence >= hardSilence
            || (silence >= sentenceEndSilence && endsSentence)
            || (seconds >= softBreakSeconds && silence >= softBreakSilence)

        if finalize {
            lock.lock()
            if segment.count >= snapshot.count {
                segment.removeFirst(snapshot.count)
            } else {
                segment.removeAll()
            }
            hasSpeech = false
            trailingSilenceSamples = 0
            lock.unlock()
            emitFinal(text)
        } else {
            onUpdate?(TranscriptUpdate(text: text, isFinal: false))
        }
    }

    private func endsWithTerminator(_ text: String) -> Bool {
        guard let last = text.reversed().first(where: { !$0.isWhitespace }) else { return false }
        return terminators.contains(last)
    }

    /// 把一整段轉錄結果依標點切成數句,各自送一筆 final。
    /// 過濾純標點/符號的碎片,並去掉與前一句連續重複的內容(Whisper 在音樂/笑聲常重複)。
    private func emitFinal(_ text: String) {
        for sentence in Self.splitSentences(text) {
            guard Self.hasMeaningfulContent(sentence) else { continue }
            guard sentence != lastEmittedFinal else { continue }
            lastEmittedFinal = sentence
            onUpdate?(TranscriptUpdate(text: sentence, isFinal: true))
        }
    }

    /// 是否含有實際文字(非全是標點/符號/空白)。
    private static func hasMeaningfulContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func splitSentences(_ text: String) -> [String] {
        let terminators: Set<Character> = [".", "?", "!", "。", "?", "!", "…"]
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if terminators.contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    private func transcribe(_ samples: [Float]) async throws -> String {
        guard let whisperKit, samples.count > sampleRate / 10 else { return "" } // 需要 > 0.1 秒
        let options = DecodingOptions(task: .transcribe, language: languageCode)
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func floatArray(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
    }

    private func drain() -> ([Float], Bool) {
        lock.lock()
        defer {
            segment.removeAll()
            hasSpeech = false
            trailingSilenceSamples = 0
            lock.unlock()
        }
        return (segment, hasSpeech)
    }
}

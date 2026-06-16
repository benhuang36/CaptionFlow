import Foundation
import AVFoundation
import CoreMedia
import Speech

/// 用 macOS 26 的 SpeechAnalyzer / SpeechTranscriber 做串流語音轉文字。
///
/// 流程:建立 transcriber → 確認語言模型已安裝(必要時下載)→ 取得 analyzer
/// 想要的音訊格式 → 把 SCK 的 buffer 轉檔後餵入 → 訂閱 results(volatile = partial、
/// final = 定稿)。
final class SpeechAnalyzerTranscriber: TranscriptionService {
    var onUpdate: ((TranscriptUpdate) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?
    private let converter = BufferConverter()

    func start(sourceLanguage: Language) async throws {
        let locale = try await Self.resolveSupportedLocale(for: sourceLanguage)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        try await Self.ensureModelInstalled(for: transcriber, locale: locale)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        // 訂閱結果
        resultsTask = Task { [weak self] in
            guard let self, let transcriber = self.transcriber else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let update = TranscriptUpdate(text: text, isFinal: result.isFinal)
                    await MainActor.run { self.onUpdate?(update) }
                }
            } catch {
                // 結果串流結束或出錯;停止時的正常路徑也會走到這裡。
            }
        }

        // 建立輸入串流並啟動分析
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = continuation
        try await analyzer.start(inputSequence: stream)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard let inputBuilder, let analyzerFormat else { return }
        do {
            let pcm = try PCMBufferFactory.make(from: sampleBuffer)
            let converted = try converter.convert(pcm, to: analyzerFormat)
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        } catch {
            // 單一緩衝轉檔失敗就略過,不中斷整體串流。
        }
    }

    func stop() async {
        inputBuilder?.finish()
        inputBuilder = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        analyzerFormat = nil
    }

    // MARK: - Locale / 模型資產

    /// 把使用者選的語言對應到「裝置端實際支援」的 locale。
    /// 先試完全相符,再退而求其次:同語言 + 同地區 → 同語言 + 同書寫系統 → 同語言任一。
    /// 例:系統地區為台灣時,自動偵測得到的 en_TW 會對應到 en-US。
    private static func resolveSupportedLocale(for language: Language) async throws -> Locale {
        let requested = language.isAuto ? Locale.current : Locale(identifier: language.code)
        let supported = await SpeechTranscriber.supportedLocales

        let requestedBCP47 = requested.identifier(.bcp47)
        if let exact = supported.first(where: { $0.identifier(.bcp47) == requestedBCP47 }) {
            return exact
        }

        let requestedLanguage = requested.language.languageCode?.identifier
        let candidates = supported.filter { $0.language.languageCode?.identifier == requestedLanguage }
        guard !candidates.isEmpty else {
            let id = requested.identifier
            throw NSError(domain: "CaptionFlow", code: 101,
                          userInfo: [NSLocalizedDescriptionKey:
                            Localized.string("On-device transcription isn't supported for this language (\(id)) yet.")])
        }

        if let region = requested.region?.identifier,
           let match = candidates.first(where: { $0.region?.identifier == region }) {
            return match
        }
        if let requestedScript = script(of: requested),
           let match = candidates.first(where: { script(of: $0) == requestedScript }) {
            return match
        }
        return candidates[0]
    }

    /// 取得 locale 的書寫系統(顯式優先,否則用 maximal 形式推斷,例如 zh-TW → Hant)。
    private static func script(of locale: Locale) -> String? {
        if let script = locale.language.script?.identifier { return script }
        return Locale.Language(identifier: locale.language.maximalIdentifier).script?.identifier
    }

    /// 確認模型已安裝;未安裝時下載。
    private static func ensureModelInstalled(for transcriber: SpeechTranscriber,
                                             locale: Locale) async throws {
        let target = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == target }) { return }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}

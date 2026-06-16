import Foundation
import Combine

/// 串起整條流程:系統音訊 → STT → 翻譯 → 字幕。
///
/// 增量翻譯策略:partial 階段只更新原文(不翻),等 STT finalize 一句後
/// 才送翻譯。使用者體感是「原文即時跳字、譯文晚一兩秒補上」,最自然。
@MainActor
final class CaptionPipeline: ObservableObject {
    @Published private(set) var segments: [CaptionSegment] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isPreparing = false
    @Published var statusMessage = ""

    /// 轉錄與翻譯可各自切換真實/mock,方便分階段驗證。
    /// 目前:真實 STT(SpeechAnalyzer + 系統音訊)+ 真實翻譯(依設定的引擎)。
    var useMockTranscriber = false
    var useMockTranslator = false

    private let settings: AppSettings
    private let modelManager: ModelManager
    private let appleBridge: AppleTranslationBridge
    private let history: HistoryStore

    private var audio: AudioCaptureService?
    private var transcriber: TranscriptionService?
    private var translator: TranslationService?
    // 翻譯一律走「單一序列工作者」:一次只跑一句,避免多個 MLX 推論並發
    // (並發會撞 Metal command buffer 斷言、且記憶體暴增)。
    private var translationContinuation: AsyncStream<UUID>.Continuation?
    private var translationWorker: Task<Void, Never>?

    // 本次工作階段的語言,記錄歷史時使用。
    private var activeSource: Language = .auto
    private var activeTarget: Language = .auto

    init(settings: AppSettings,
         modelManager: ModelManager,
         appleBridge: AppleTranslationBridge,
         history: HistoryStore) {
        self.settings = settings
        self.modelManager = modelManager
        self.appleBridge = appleBridge
        self.history = history
    }

    func start() async {
        guard !isRunning, !isPreparing else { return }
        isPreparing = true
        settings.isCapturing = true   // 鏡射給 Settings scene:執行中鎖住「需重啟才生效」的設定
        // 讓出當前 runloop tick,避免在 SwiftUI 更新交易內就改 @Published
        // (否則會出現 "Publishing changes from within view updates" 警告)。
        await Task.yield()
        segments.removeAll()

        let source = settings.sourceLanguage
        let target = settings.targetLanguage
        activeSource = source
        activeTarget = target
        history.beginSession(source: source, target: target)

        let transcriber = makeTranscriber()
        let translator = makeTranslator()
        self.transcriber = transcriber
        self.translator = translator

        transcriber.onUpdate = { [weak self] update in
            Task { @MainActor in self?.handle(update) }
        }

        // 啟動序列翻譯工作者:逐一處理定稿的句子,絕不並發。
        let (idStream, continuation) = AsyncStream<UUID>.makeStream()
        translationContinuation = continuation
        translationWorker = Task { @MainActor [weak self] in
            for await segmentID in idStream {
                await self?.performTranslation(segmentID)
            }
        }

        do {
            statusMessage = Localized.string("Preparing translation model…")
            try await translator.prepare(source: source, target: target)

            statusMessage = Localized.string("Starting transcription…")
            try await transcriber.start(sourceLanguage: source)

            if !useMockTranscriber {
                let audio = SystemAudioCaptureService()
                audio.onAudio = { [weak transcriber] buffer in transcriber?.append(buffer) }
                audio.onError = { [weak self] error in
                    Task { @MainActor in self?.statusMessage = Localized.string("Audio stream interrupted: \(error.localizedDescription)") }
                }
                try await audio.start()
                self.audio = audio
            }

            isRunning = true
            isPreparing = false
            statusMessage = Localized.string("Running")
        } catch {
            isPreparing = false
            settings.isCapturing = false
            statusMessage = Localized.string("Failed to start: \(error.localizedDescription)")
            translationContinuation?.finish()
            translationContinuation = nil
            await translationWorker?.value
            translationWorker = nil
            await teardown()
            history.endSession()   // 啟動失敗:結算(空階段會被丟棄)
        }
    }

    func stop() async {
        isRunning = false
        settings.isCapturing = false
        statusMessage = Localized.string("Stopped")

        // 先停音訊與轉錄(transcriber 收尾可能 emit 最後一句的 final)。
        await audio?.stop(); audio = nil
        await transcriber?.stop(); transcriber = nil

        // 讓剛 finalize 的 onUpdate 排程跑完(把最後一句送進佇列),
        // 然後關閉佇列、等序列工作者把剩下的翻譯依序跑完。
        await Task.yield()
        translationContinuation?.finish()
        translationContinuation = nil
        await translationWorker?.value
        translationWorker = nil

        // 所有 GPU 翻譯都結束後,才釋放模型並清 MLX 快取
        // (否則 clearCache 撞到還在跑的推論會觸發 Metal command buffer 斷言)。
        await translator?.teardown(); translator = nil

        history.endSession()
    }

    private func teardown() async {
        await audio?.stop(); audio = nil
        await transcriber?.stop(); transcriber = nil
        await translator?.teardown(); translator = nil
    }

    // MARK: - 字幕更新

    private func handle(_ update: TranscriptUpdate) {
        if let idx = segments.lastIndex(where: { !$0.isFinal }) {
            segments[idx].sourceText = update.text
            if update.isFinal {
                segments[idx].isFinal = true
                translationContinuation?.yield(segments[idx].id)
            }
        } else {
            let segment = CaptionSegment(sourceText: update.text, isFinal: update.isFinal)
            segments.append(segment)
            if update.isFinal { translationContinuation?.yield(segment.id) }
        }
    }

    /// 翻譯時帶入的前文句數(原文+譯文配對)。太多會稀釋當前句、拖慢小模型。
    private let translationContextWindow = 3

    /// 由序列工作者呼叫:一次翻譯一句(不會並發)。
    private func performTranslation(_ segmentID: UUID) async {
        guard let translator,
              let idx = segments.firstIndex(where: { $0.id == segmentID }) else { return }
        let text = segments[idx].sourceText

        // 蒐集緊接在前、已翻好的句子當上下文(由舊到新),供 LLM 理解語境。
        let context: [TranslationContextLine] = segments[..<idx]
            .compactMap { seg -> TranslationContextLine? in
                guard let t = seg.translatedText, !t.isEmpty else { return nil }
                return TranslationContextLine(source: seg.sourceText, translated: t)
            }
            .suffix(translationContextWindow)
            .map { $0 }

        let result = try? await translator.translate(text, context: context)
        if let result, let i = segments.firstIndex(where: { $0.id == segmentID }) {
            segments[i].translatedText = result
        }
        // 不論顯示模式,原文與譯文都存進目前工作階段。
        history.appendLine(sourceText: text, translatedText: result ?? "")
    }

    // MARK: - 服務組裝

    private func makeTranscriber() -> TranscriptionService {
        guard !useMockTranscriber else { return MockTranscriptionService() }
        switch settings.sttEngine {
        case .appleSpeech:
            return SpeechAnalyzerTranscriber()
        case .whisperKit:
            let service = WhisperKitTranscriber(model: settings.whisperModel.rawValue)
            service.onProgress = { [weak self] fraction in
                Task { @MainActor in
                    let pct = String(format: "%.0f%%", fraction * 100)
                    self?.statusMessage = Localized.string("Downloading Whisper model… \(pct)")
                }
            }
            return service
        }
    }

    private func makeTranslator() -> TranslationService {
        guard !useMockTranslator else { return MockTranslationService() }
        switch settings.translationEngine {
        case .localLLM:
            let service = MLXTranslationService(model: modelManager.effectiveModel(for: settings))
            service.onProgress = { [weak self] fraction in
                Task { @MainActor in
                    let pct = String(format: "%.0f%%", fraction * 100)
                    self?.statusMessage = Localized.string("Downloading/loading model… \(pct)")
                }
            }
            return service
        case .appleTranslation:
            return AppleTranslationService(bridge: appleBridge)
        }
    }
}

import SwiftUI

struct MainView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var modelManager: ModelManager
    @StateObject private var pipeline: CaptionPipeline
    @StateObject private var translationBridge: AppleTranslationBridge

    init(settings: AppSettings, modelManager: ModelManager, history: HistoryStore) {
        let bridge = AppleTranslationBridge()
        _translationBridge = StateObject(wrappedValue: bridge)
        _pipeline = StateObject(
            wrappedValue: CaptionPipeline(settings: settings,
                                          modelManager: modelManager,
                                          appleBridge: bridge,
                                          history: history)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ControlBar(pipeline: pipeline)
            Divider()
            CaptionListView(segments: pipeline.segments,
                            displayMode: settings.displayMode)
            Divider()
            StatusBar(pipeline: pipeline, engineLabel: engineLabel)
        }
        .background(AppleTranslationHost(bridge: translationBridge))
    }

    private var engineLabel: String {
        switch settings.translationEngine {
        case .appleTranslation:
            return Localized.string("Translation: Apple Translation")
        case .localLLM:
            if settings.usesCustomTranslationEndpoint {
                return Localized.string("Translation: Custom API")
            }
            return Localized.string("Model: \(modelManager.effectiveModel(for: settings).displayName)")
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var pipeline: CaptionPipeline
    let engineLabel: String

    var body: some View {
        HStack {
            Circle()
                .fill(pipeline.isRunning ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            // statusMessage 已在來源處在地化(Localized.string);空時顯示在地化的「閒置」。
            Group {
                if pipeline.statusMessage.isEmpty {
                    Text("Idle")
                } else {
                    Text(verbatim: pipeline.statusMessage)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Text(engineLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

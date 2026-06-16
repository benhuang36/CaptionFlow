import SwiftUI

struct ControlBar: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var pipeline: CaptionPipeline
    @Environment(\.openWindow) private var openWindow
    @State private var showingAudioTest = false

    var body: some View {
        HStack(spacing: 12) {
            languagePicker("Source", selection: sourceBinding, options: Language.sourceOptions)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            languagePicker("Target", selection: targetBinding, options: Language.targetOptions)

            Divider().frame(height: 20)

            Picker("Display", selection: displayModeBinding) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()

            Spacer()

            Button {
                openWindow(id: "history")
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("History")

            Button {
                showingAudioTest = true
            } label: {
                Image(systemName: "waveform")
            }
            .help("Audio Capture Test")

            Button {
                Task {
                    if pipeline.isRunning { await pipeline.stop() }
                    else { await pipeline.start() }
                }
            } label: {
                if pipeline.isPreparing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Preparing…")
                    }
                } else if pipeline.isRunning {
                    Label("Stop", systemImage: "stop.fill")
                } else {
                    Label("Start", systemImage: "play.fill")
                }
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(pipeline.isRunning ? .red : .accentColor)
            .disabled(pipeline.isPreparing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingAudioTest) {
            AudioTestView()
        }
    }

    private func languagePicker(_ title: LocalizedStringKey,
                                selection: Binding<String>,
                                options: [Language]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { lang in
                // 語言自稱以原文呈現;唯「自動偵測」需在地化。
                if lang.isAuto {
                    Text("Auto Detect").tag(lang.code)
                } else {
                    Text(verbatim: lang.displayName).tag(lang.code)
                }
            }
        }
        .fixedSize()
    }

    private var sourceBinding: Binding<String> {
        Binding(get: { settings.sourceLanguageCode },
                set: { settings.sourceLanguageCode = $0 })
    }
    private var targetBinding: Binding<String> {
        Binding(get: { settings.targetLanguageCode },
                set: { settings.targetLanguageCode = $0 })
    }
    private var displayModeBinding: Binding<DisplayMode> {
        Binding(get: { settings.displayMode },
                set: { settings.displayMode = $0 })
    }
}

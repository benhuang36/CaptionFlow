import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ModelSettingsView()
                .tabItem { Label("Translation Model", systemImage: "cpu") }
        }
        .frame(width: 500)
    }
}

// MARK: - 一般(STT / 翻譯引擎)

private struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var whisperDownloads: WhisperDownloadManager

    var body: some View {
        Form {
            Section("Speech Recognition (STT)") {
                Picker("Recognition Engine", selection: sttBinding) {
                    ForEach(STTEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                if settings.sttEngine == .whisperKit {
                    Picker("Whisper Model", selection: whisperBinding) {
                        ForEach(WhisperModelOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } else {
                    Text("Apple speech recognition streams natively with the best integration; for some languages WhisperKit may work better.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.sttEngine == .whisperKit {
                Section("Whisper Model Downloads") {
                    ForEach(WhisperModelOption.allCases) { option in
                        DownloadControlRow(manager: whisperDownloads,
                                           key: option.rawValue,
                                           title: option.rawValue,
                                           hint: "")
                    }
                    Text("For multilingual audio (e.g. Japanese) Whisper is usually more reliable than Apple; large-v3 has the best quality but is larger and slower.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Translation") {
                Picker("Translation Engine", selection: engineBinding) {
                    ForEach(TranslationEngine.allCases) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                Text("Use the on-device LLM for best quality; switch to Apple Translation when memory is tight or you want the lowest latency.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Language") {
                Picker("Language", selection: languageBinding) {
                    ForEach(AppSettings.appLanguageOptions, id: \.code) { option in
                        if option.code == "system" {
                            Text("System default").tag(option.code)
                        } else {
                            Text(verbatim: option.endonym).tag(option.code)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            whisperDownloads.refresh(keys: WhisperModelOption.allCases.map(\.rawValue))
        }
    }

    private var engineBinding: Binding<TranslationEngine> {
        Binding(get: { settings.translationEngine }, set: { settings.translationEngine = $0 })
    }
    private var languageBinding: Binding<String> {
        Binding(get: { settings.appLanguage }, set: { settings.setAppLanguage($0) })
    }
    private var sttBinding: Binding<STTEngine> {
        Binding(get: { settings.sttEngine }, set: { settings.sttEngine = $0 })
    }
    private var whisperBinding: Binding<WhisperModelOption> {
        Binding(get: { settings.whisperModel }, set: { settings.whisperModel = $0 })
    }
}

// MARK: - 翻譯模型(LLM)

private struct ModelSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var llmDownloads: LLMDownloadManager

    var body: some View {
        Form {
            Section("This Mac") {
                LabeledContent("Physical Memory",
                               value: String(format: "%.0f GB", modelManager.profile.totalRAMGB))
                LabeledContent("Available for LLM",
                               value: String(format: "~%.1f GB", modelManager.profile.llmBudgetGB))
                LabeledContent("Recommended Model", value: modelManager.recommended.displayName)
            }

            Section("Model Selection") {
                Toggle("Auto-recommend based on memory", isOn: autoBinding)
                Picker("Manual selection", selection: modelBinding) {
                    ForEach(modelManager.catalog) { model in
                        Text(rowLabel(for: model)).tag(model.id)
                    }
                }
                .disabled(settings.autoSelectModel)
                Text("In use: \(modelManager.effectiveModel(for: settings).displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Downloads") {
                ForEach(modelManager.catalog) { model in
                    DownloadControlRow(manager: llmDownloads,
                                       key: model.id,
                                       title: model.displayName,
                                       hint: String(format: "~%.1f GB", model.approxRAMGB))
                }
                Text("Model files are stored in ~/Library/Caches; deleting one re-downloads it on next use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if settings.selectedModelID.isEmpty {
                settings.selectedModelID = modelManager.recommended.id
            }
            llmDownloads.refresh(keys: modelManager.catalog.map(\.id))
        }
    }

    private func rowLabel(for model: LLMModel) -> String {
        let fits = modelManager.canRun(model)
        let ram = String(format: "%.1f GB", model.approxRAMGB)
        return "\(model.displayName) · \(ram)" + (fits ? "" : " · " + Localized.string("may exceed memory"))
    }

    private var autoBinding: Binding<Bool> {
        Binding(get: { settings.autoSelectModel }, set: { settings.autoSelectModel = $0 })
    }
    private var modelBinding: Binding<String> {
        Binding(get: { settings.selectedModelID }, set: { settings.selectedModelID = $0 })
    }
}

// MARK: - 共用下載列(下載 / 進度+取消 / 刪除)

private struct DownloadControlRow: View {
    @ObservedObject var manager: DownloadManager
    let key: String
    let title: String
    let hint: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        switch manager.status(forKey: key) {
        case .notDownloaded:
            Button("Download") { manager.download(key: key) }
        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 80)
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { manager.cancel(key: key) } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Cancel download")
            }
        case .downloaded:
            Button("Delete", role: .destructive) { manager.delete(key: key) }
        }
    }

    private var statusText: String {
        switch manager.status(forKey: key) {
        case .notDownloaded:
            return hint.isEmpty ? Localized.string("Not downloaded")
                                : Localized.string("Not downloaded · \(hint)")
        case .downloading:
            return Localized.string("Downloading…")
        case .downloaded(let bytes):
            let gb = String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
            return Localized.string("Downloaded · \(gb)")
        }
    }
}

import SwiftUI
import AppKit

/// Cmd+Q / 選單離開時,先把執行中的 pipeline 優雅關閉(停掉並收乾 MLX GPU 工作),
/// 才讓程序真正結束。否則 MLX 的 Metal device 會在還有命令緩衝在飛時被摧毀 → 崩潰。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let pipeline = CaptionPipeline.active,
                  pipeline.isRunning || pipeline.isPreparing else {
                return .terminateNow
            }
            Task {
                await pipeline.stop()
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}

@main
struct CaptionFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings()
    @StateObject private var modelManager = ModelManager()
    @StateObject private var history = HistoryStore()

    @StateObject private var llmDownloads = LLMDownloadManager(
        isDownloaded: { ModelStorage.isDownloaded(repoId: $0) },
        size: { ModelStorage.sizeOnDisk(repoId: $0) },
        download: { id, progress in try await ModelStorage.download(repoId: id, progress: progress) },
        delete: { try ModelStorage.delete(repoId: $0) }
    )
    @StateObject private var whisperDownloads = WhisperDownloadManager(
        isDownloaded: { WhisperModelStorage.isDownloaded(variant: $0) },
        size: { WhisperModelStorage.sizeOnDisk(variant: $0) },
        download: { variant, progress in try await WhisperModelStorage.download(variant: variant, progress: progress) },
        delete: { try WhisperModelStorage.delete(variant: $0) }
    )

    var body: some Scene {
        WindowGroup {
            MainView(settings: settings, modelManager: modelManager, history: history)
                .environmentObject(settings)
                .environmentObject(modelManager)
                .environmentObject(history)
                .environmentObject(llmDownloads)
                .environmentObject(whisperDownloads)
                .frame(minWidth: 560, minHeight: 360)
                .environment(\.locale, settings.locale)
        }
        .windowResizability(.contentMinSize)

        Window("History", id: "history") {
            HistoryView()
                .environmentObject(history)
                .frame(minWidth: 460, minHeight: 320)
                .environment(\.locale, settings.locale)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(modelManager)
                .environmentObject(llmDownloads)
                .environmentObject(whisperDownloads)
                .environment(\.locale, settings.locale)
        }
    }
}

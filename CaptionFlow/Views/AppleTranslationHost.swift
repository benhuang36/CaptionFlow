import SwiftUI
import Translation

/// 隱藏的 host:唯一目的是透過 `.translationTask` 取得 TranslationSession,
/// 交給 bridge 處理翻譯佇列。掛在主畫面背景即可。
struct AppleTranslationHost: View {
    @ObservedObject var bridge: AppleTranslationBridge

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(bridge.configuration) { session in
                await bridge.process(using: session)
            }
    }
}

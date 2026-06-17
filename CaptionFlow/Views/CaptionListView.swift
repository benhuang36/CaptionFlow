import SwiftUI

struct CaptionListView: View {
    let segments: [CaptionSegment]
    let displayMode: DisplayMode

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if segments.isEmpty {
                    emptyState
                } else {
                    // 整份逐字稿用單一可選取的 Text 呈現,支援 Cmd+A 全選、Cmd+C 複製。
                    Text(transcript)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                Color.clear.frame(height: 1).id(Self.bottomAnchor)
            }
            .onChange(of: segments.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: segments.last?.sourceText) { _, _ in scrollToBottom(proxy) }
        }
        .frame(maxHeight: .infinity)
    }

    private static let bottomAnchor = "bottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    /// 即時字幕只繪最近這麼多句。整份逐字稿每次 partial 都重建,若繪全部,
    /// 跑久了會越來越卡(O(全部) × 每秒約兩次)。完整內容仍存於歷史記錄。
    private static let maxRenderedSegments = 60

    private var transcript: AttributedString {
        var result = AttributedString()
        let recent = segments.suffix(Self.maxRenderedSegments)
        let lastOffset = recent.count - 1
        for (offset, segment) in recent.enumerated() {
            if displayMode.showsSource {
                var line = AttributedString(segment.sourceText)
                line.font = .title3
                line.foregroundColor = segment.isFinal ? .primary : .secondary
                result += line
                result += AttributedString("\n")
            }
            if displayMode.showsTarget {
                if let translated = segment.translatedText {
                    var line = AttributedString(translated)
                    line.font = displayMode == .targetOnly ? .title3 : .body
                    line.foregroundColor = displayMode == .targetOnly ? .primary : .secondary
                    result += line
                    result += AttributedString("\n")
                } else if segment.isFinal {
                    var line = AttributedString(Localized.string("Translating…"))
                    line.font = .body
                    line.foregroundColor = .secondary
                    result += line
                    result += AttributedString("\n")
                }
            }
            if offset < lastOffset {
                result += AttributedString("\n")
            }
        }
        return result
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Press Start to show live captions")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

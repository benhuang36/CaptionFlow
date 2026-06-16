import SwiftUI

struct AudioTestView: View {
    @StateObject private var diagnostic = AudioCaptureDiagnostic()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Audio Capture Test")
                .font(.headline)

            // status 已在來源處在地化(Localized.string),verbatim 顯示。
            Text(verbatim: diagnostic.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            LevelMeter(level: diagnostic.level, peak: diagnostic.peak)
                .frame(height: 22)

            LabeledContent("Buffers received", value: "\(diagnostic.bufferCount)")
                .font(.callout)

            HStack {
                Button {
                    Task {
                        if diagnostic.isRunning { await diagnostic.stop() }
                        else { await diagnostic.start() }
                    }
                } label: {
                    if diagnostic.isRunning { Text("Stop") } else { Text("Start Capture") }
                }
                .buttonStyle(.borderedProminent)

                Button("Close") {
                    Task { await diagnostic.stop(); dismiss() }
                }
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

private struct LevelMeter: View {
    let level: Float
    let peak: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [.green, .yellow, .orange],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, geo.size.width * CGFloat(level)))
                    .animation(.linear(duration: 0.05), value: level)

                // 峰值指示線
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2)
                    .offset(x: geo.size.width * CGFloat(peak) - 1)
                    .opacity(peak > 0.01 ? 0.7 : 0)
            }
        }
    }
}

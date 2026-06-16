import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var selection = Set<UUID>()

    /// 最新的在最上面。
    private var sessions: [HistorySession] {
        history.sessions.reversed()
    }

    private var focusedSession: HistorySession? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return history.sessions.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if history.sessions.isEmpty {
                    ContentUnavailableView("No History Yet",
                                           systemImage: "clock",
                                           description: Text("Each Start → Stop is saved as one entry."))
                } else {
                    List(selection: $selection) {
                        ForEach(sessions) { session in
                            SessionRow(session: session)
                                .tag(session.id)
                                .contextMenu {
                                    Button("Delete", role: .destructive) { history.delete(session) }
                                }
                        }
                    }
                    .onDeleteCommand { deleteSelected() }
                }
            }
            .frame(minWidth: 220)
            .navigationTitle("History")
            .toolbar {
                ToolbarItemGroup {
                    Button(role: .destructive, action: deleteSelected) {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .disabled(selection.isEmpty)

                    Button(role: .destructive) { history.clearAll() } label: {
                        Label("Clear All", systemImage: "trash.slash")
                    }
                    .disabled(history.sessions.isEmpty)
                }
            }
        } detail: {
            if let session = focusedSession {
                SessionDetail(session: session)
            } else {
                ContentUnavailableView("Select an Entry",
                                       systemImage: "text.bubble",
                                       description: Text("Pick a session on the left to view the source and translation."))
            }
        }
    }

    private func deleteSelected() {
        history.delete(ids: selection)
        selection.removeAll()
    }
}

private struct SessionRow: View {
    let session: HistorySession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.body)
            Text(verbatim: session.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SessionDetail: View {
    let session: HistorySession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                Text(transcript)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .toolbar {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(plainText, forType: .string)
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.startDate.formatted(date: .complete, time: .standard))
                .font(.headline)
            Text(verbatim: session.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var transcript: AttributedString {
        var result = AttributedString()
        for (index, line) in session.lines.enumerated() {
            var source = AttributedString(line.sourceText)
            source.font = .title3
            source.foregroundColor = .primary
            result += source
            result += AttributedString("\n")

            var translated = AttributedString(line.translatedText.isEmpty ? Localized.string("(no translation)") : line.translatedText)
            translated.font = .body
            translated.foregroundColor = .secondary
            result += translated

            if index < session.lines.count - 1 {
                result += AttributedString("\n\n")
            }
        }
        return result
    }

    private var plainText: String {
        session.lines.map { line in
            line.translatedText.isEmpty ? line.sourceText : "\(line.sourceText)\n\(line.translatedText)"
        }.joined(separator: "\n\n")
    }
}

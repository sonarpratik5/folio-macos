import SwiftUI
import FolioCore

struct ConversationsView: View {
    @ObservedObject var workspace: Workspace
    @State private var entries: [ConversationEntry] = []
    @State private var query = ""
    @State private var failure: String?
    @State private var loading = false
    @State private var matches: [ConversationEntry] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FolioHeader("Conversations", subtitle: "Search saved chats across all your papers. Everything stays on this Mac.")
            TextField("Search papers, chat titles and messages", text: $query).textFieldStyle(.roundedBorder)
            if loading { ProgressView() }
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
            List(matches) { entry in
                Button {
                    if let paper = workspace.papers.first(where: { $0.id == entry.paperID }) { workspace.resumeChat(entry.id, for: paper) }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title).font(.headline)
                        Text(entry.paperTitle).foregroundStyle(.secondary)
                        Text(entry.content.prefix(240)).font(.callout).lineLimit(2)
                    }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if !loading && matches.isEmpty { Text("No matching conversations.").foregroundStyle(.secondary) }
        }.padding(24).navigationTitle("Conversations")
        .task {
            guard let root = workspace.repository?.root else { return }
            let records = workspace.papers.map { ($0.id, $0.title) }
            loading = true
            let result = await Task.detached(priority: .userInitiated) {
                ConversationIndex.load(root: root, papers: records)
            }.value
            guard !Task.isCancelled else { return }
            entries = result.entries; matches = result.entries; failure = result.failures > 0 ? "\(result.failures) saved chat file(s) could not be read; their files were kept." : nil
            loading = false
        }
        .task(id: "\(entries.count):\(query)") {
            let value = query
            let source = entries
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            let filtered = await Task.detached(priority: .userInitiated) { source.filter { $0.matches(value) } }.value
            guard !Task.isCancelled else { return }
            matches = filtered
        }
    }
}

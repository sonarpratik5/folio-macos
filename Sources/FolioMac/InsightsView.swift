import SwiftUI
import PDFKit
import FolioCore

/// Paper context comes before reading; inspection never replaces the active PDF or its saved position.
struct InsightsView: View {
    @ObservedObject var workspace: Workspace
    private var selected: PaperRecord? {
        workspace.papers.first { $0.id == workspace.insightsPaperID }
            ?? workspace.activePaper ?? workspace.papers.max { $0.lastOpened < $1.lastOpened }
    }

    var body: some View {
        Group {
            if let selected {
                InsightsPaper(workspace: workspace, paper: selected).id(selected.id)
            } else {
                ContentUnavailableView {
                    Label("No papers yet", systemImage: "lightbulb")
                } description: {
                    Text("Import a PDF to view its overview.")
                } actions: {
                    Button("Import PDF…", action: workspace.choosePDF).disabled(workspace.repository == nil)
                }
            }
        }.navigationTitle("Insights")
    }
}

private struct InsightsPaper: View {
    @ObservedObject var workspace: Workspace
    let paper: PaperRecord
    @StateObject private var model = PaperAssistantModel()
    @State private var tab = "overview"
    @State private var showAllChats = false
    @State private var notes: [PaperNote] = []
    @State private var outline: [SectionLink] = []
    @State private var deleting: AssistantThread?

    private struct SectionLink: Identifiable {
        let id: Int
        let title: String
        let page: Int
        let depth: Int
    }
    private var chats: [AssistantThread] {
        (model.threads?.threads ?? []).filter { !$0.turns.isEmpty }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var paperIndex: Int { workspace.papers.firstIndex { $0.id == paper.id } ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    navigation
                    header
                    FolioUnderlineTabs(items: [.init(id: "overview", title: "Overview"), .init(id: "notes", title: "Notes")], selection: $tab)
                    if tab == "overview" {
                        if geometry.size.width >= 860 {
                            HStack(alignment: .top, spacing: 24) {
                                context.frame(maxWidth: .infinity)
                                contents.frame(width: 260)
                            }
                        } else {
                            context
                            contents
                        }
                        conversations
                    } else {
                        paperNotes
                    }
                }
                .frame(maxWidth: 1400, alignment: .leading)
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .onAppear(perform: load)
        .onDisappear { model.cancel() }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Chat", role: .destructive) { if let id = deleting?.id { model.delete(id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This removes the conversation from this Mac. It cannot be undone.") }
    }

    private var navigation: some View {
        HStack {
            Button { workspace.navigate(to: .all) } label: { Label("All documents", systemImage: "arrow.left") }
            Spacer()
            Button { adjacent(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(paperIndex == 0).accessibilityLabel("Previous paper")
            Text("\(paperIndex + 1) of \(workspace.papers.count)").font(.caption).foregroundStyle(.secondary)
            Button { adjacent(1) } label: { Image(systemName: "chevron.right") }
                .disabled(paperIndex + 1 >= workspace.papers.count).accessibilityLabel("Next paper")
        }.buttonStyle(.plain).foregroundStyle(FolioTheme.accent)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            if let repository = workspace.repository {
                PaperThumbnail(url: repository.documentURL(for: paper.id), padding: 0)
                    .frame(width: 90, height: 120).background(FolioTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(FolioTheme.line))
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(paper.title).font(FolioTheme.heading(32)).textSelection(.enabled).accessibilityAddTraits(.isHeader)
                if let author = paper.author { Text(author).foregroundStyle(.secondary) }
                Text(metadata).font(.callout).foregroundStyle(.secondary)
                Button { workspace.open(paper) } label: {
                    Label(paper.currentPage > 1 ? "Resume on page \(paper.currentPage)" : "Read paper", systemImage: "arrow.up.right")
                }.buttonStyle(FolioPrimaryButtonStyle())
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8)
    }

    private var metadata: String {
        var parts = ["\(paper.pageCount) pages"]
        if let insights = model.insights { parts += ["\(insights.words.formatted()) words", "~\(insights.minutes) min read"] }
        return parts.joined(separator: "  ·  ")
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 24) {
            GlancePanel(workspace: workspace, model: model, paper: paper)
            VStack(alignment: .leading, spacing: 18) {
                FolioTheme.overline("Abstract")
                if let insights = model.insights {
                    Text(insights.abstract.isEmpty ? "No abstract could be extracted from this PDF’s text layer. Open the paper to read its introduction." : insights.abstract)
                        .font(.system(size: 17, design: .serif)).lineSpacing(7)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if !insights.keywords.isEmpty {
                        FolioTheme.overline("Key terms").padding(.top, 8)
                        GlanceTags(tags: insights.keywords.map(\.term))
                    }
                    Text("Taken from the paper’s text on this Mac.").font(.caption).foregroundStyle(.secondary)
                } else if model.paper == nil {
                    Text("The paper text is unavailable.").foregroundStyle(.secondary)
                } else {
                    ProgressView("Reading the text layer…").controlSize(.small)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).folioCard(padding: 24)
        }
    }

    private var contents: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Contents", systemImage: "list.bullet.indent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if outline.isEmpty {
                Text("This PDF has no embedded outline.").font(.callout).foregroundStyle(.secondary)
                Button("Read from page 1") { workspace.open(paper, at: 1) }.buttonStyle(.link)
            } else {
                ForEach(outline) { section in
                    Button { workspace.open(paper, at: section.page) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(section.page.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
                            Text(section.title).font(.callout).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }.padding(.leading, CGFloat(min(section.depth, 3)) * 10).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).help("Read page \(section.page)")
                    if section.id != outline.last?.id { Divider() }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).folioCard(padding: 20)
    }

    private var conversations: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FolioTheme.overline("Recent conversations")
                Spacer()
                if chats.count > 2 {
                    Button(showAllChats ? "Show recent" : "View all (\(chats.count))") { showAllChats.toggle() }.buttonStyle(.link)
                }
                Button("New chat") {
                    workspace.present(.assistant, for: paper)
                    guard workspace.reading, workspace.activeID == paper.id, let assistant = workspace.activeAIStore?.assistant else { return }
                    assistant.load(root: workspace.repository?.root, record: paper)
                    assistant.newThread()
                }.buttonStyle(.link)
            }
            if chats.isEmpty {
                Text("No conversations about this paper yet.").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).folioCard(padding: 20)
            }
            ForEach(Array(chats.prefix(showAllChats ? chats.count : 2))) { thread in
                HStack(alignment: .center, spacing: 16) {
                    Button { workspace.resumeChat(thread.id, for: paper) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Label(paper.title, systemImage: "bubble.left").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(thread.title).font(.headline).lineLimit(1)
                            if let answer = thread.turns.last(where: { $0.role == .assistant }) {
                                Text(answer.content).font(.system(size: 15, design: .serif)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            HStack {
                                Text("\(thread.updatedAt.formatted(.relative(presentation: .named))) · \(thread.turns.filter { $0.role == .user }.count) questions").foregroundStyle(.secondary)
                                Spacer()
                                Text("Continue chat ↗").foregroundStyle(FolioTheme.accent)
                            }.font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { deleting = thread } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(model.busy).accessibilityLabel("Delete chat: \(thread.title)")
                }.folioCard(padding: 18)
            }
        }
    }

    private var paperNotes: some View {
        VStack(alignment: .leading, spacing: 16) {
            if notes.isEmpty { Text("No notes on this paper yet.").foregroundStyle(.secondary) }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 10) {
                    Text(note.body).textSelection(.enabled)
                    Button("Read page \(note.page)") { workspace.open(paper, at: note.page) }.buttonStyle(.link)
                }.frame(maxWidth: .infinity, alignment: .leading).folioCard(padding: 20)
            }
        }
    }

    private func adjacent(_ offset: Int) {
        let index = paperIndex + offset
        if workspace.papers.indices.contains(index) { workspace.showInsights(for: workspace.papers[index]) }
    }

    private func load() {
        model.load(root: workspace.repository?.root, record: paper)
        model.loadInsights()
        guard let url = workspace.repository?.documentURL(for: paper.id), let document = PDFDocument(url: url) else { return }
        notes = PDFNotes.read(from: document)
        var links: [SectionLink] = []
        func walk(_ node: PDFOutline, depth: Int) {
            guard depth < 20 else { return }
            for index in 0..<node.numberOfChildren {
                guard links.count < 600, let child = node.child(at: index) else { break }
                if let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination,
                   let page = destination.page {
                    let number = document.index(for: page)
                    if number != NSNotFound { links.append(SectionLink(id: links.count, title: child.label ?? "Untitled section", page: number + 1, depth: depth)) }
                }
                walk(child, depth: depth + 1)
            }
        }
        if let root = document.outlineRoot { walk(root, depth: 0) }
        outline = links
    }
}

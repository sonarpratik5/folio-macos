import SwiftUI
import PDFKit
import FolioCore

@MainActor
final class PaperReviewsModel: ObservableObject {
    @Published var saved: SavedPaperReviews?
    @Published var paperText: AssistantPaper?
    @Published var candidates: [ReviewCandidate] = []
    @Published var error: String?
    @Published var message = ""
    @Published var busy = false
    private var repository: NativeReviewRepository?
    private var task: Task<Void, Never>?
    private var loaded = false
    private let reviews: NativeReviewsClient
    private let analysis: NativeReviewAnalysisService
    init(reviews: NativeReviewsClient = NativeReviewsClient(), analysis: NativeReviewAnalysisService = NativeReviewAnalysisService()) { self.reviews = reviews; self.analysis = analysis }

    func load(root: URL?, record: PaperRecord) {
        guard !loaded else { return }; loaded = true
        guard let root else { error = "The local library is unavailable."; return }
        do {
            let url = root.appendingPathComponent("Documents").appendingPathComponent(record.id.uuidString).appendingPathExtension("pdf")
            guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount == record.pageCount else { throw AssistantError.message("This managed PDF could not be read.") }
            let paper = try AssistantPaper(title: record.title, pages: (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" })
            let repository = NativeReviewRepository(root: root, paperID: record.id, paper: paper)
            let saved = try repository.load()
            self.repository = repository; self.saved = saved; paperText = paper
        } catch { self.error = error.localizedDescription }
    }
    func find(title: String) {
        guard paperText != nil else { return }
        begin("Looking for matching public review forums…") {
            let candidates = try await self.reviews.search(title: title)
            try Task.checkCancellation()
            self.candidates = candidates
            self.message = candidates.isEmpty ? "No matching forum was found. Try the paper’s full title or paste an OpenReview link." : "Choose the matching paper below. Finding reviews does not run AI analysis."
        }
    }
    func fetch(_ input: String) {
        guard let saved else { return }
        begin("Reading the OpenReview thread…") {
            let forum = try await self.reviews.forum(input)
            try Task.checkCancellation()
            var next = saved; next.forum = forum; next.analysis = nil
            try self.repository?.save(next)
            self.saved = next; self.candidates = []
            self.message = forum.hasReviews ? "Public review thread loaded. Choose Analyze reviews to send excerpts to your selected AI provider." : "This forum has no public review or meta-review notes yet."
        }
    }
    func analyze(provider: AssistantProvider) {
        guard let saved, let forum = saved.forum, let paper = paperText else { return }
        begin("Comparing reviewer concerns with the paper…") {
            let result = try await self.analysis.analyze(forum: forum, paper: paper, provider: provider)
            try Task.checkCancellation()
            var next = saved; next.analysis = result
            try self.repository?.save(next); self.saved = next
            self.message = "Review analysis saved locally. Check the exact quotations and paper sources before drawing conclusions."
        }
    }
    private func begin(_ status: String, operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil; message = status
        task = Task {
            defer { self.busy = false; self.task = nil }
            do { try await operation() }
            catch is CancellationError { self.message = "Cancelled." }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func cancel() { task?.cancel() }
}

/// Compact peer-reviews section for the reader's right panel. State lives in `PaperAIStore`, so it is not cancelled on disappear.
struct ReviewsPanel: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var model: PaperReviewsModel
    let paper: PaperRecord
    @AppStorage("folio.assistant.provider") private var providerValue = AssistantProvider.codex.rawValue
    @State private var title = ""
    @State private var forumInput = ""
    private var provider: AssistantProvider { AssistantProvider(rawValue: providerValue) ?? .codex }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(workspace: workspace, eyebrow: "Folio AI", title: "Peer reviews")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        FolioTheme.overline("Find public OpenReview reviews")
                        TextField("Paper title", text: $title).textFieldStyle(.roundedBorder)
                        Button("Find reviews") { model.find(title: title) }
                            .disabled(model.busy || model.paperText == nil || title.count < 8)
                        TextField("OpenReview link or forum ID", text: $forumInput).textFieldStyle(.roundedBorder)
                        Button("Load thread") { model.fetch(forumInput) }
                            .disabled(model.busy || model.paperText == nil || NativeReviewsClient.forumID(forumInput) == nil)
                        Text("Searches OpenReview by title or loads a public thread from a link.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.folioCard(padding: FolioSpace.m)
                    if model.busy {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.message.isEmpty ? "Working…" : model.message).font(.callout) }
                            Button("Cancel") { model.cancel() }
                        }.frame(maxWidth: .infinity, alignment: .leading).folioCard(radius: FolioRadius.control, padding: 10)
                    } else if !model.message.isEmpty && model.error == nil { FolioNotice(text: model.message) }
                    if let error = model.error { FolioNotice(text: error, tone: .error) }
                    if model.saved?.forum == nil, model.candidates.isEmpty, model.error == nil, !model.busy {
                        VStack(spacing: 8) {
                            Image(systemName: "text.bubble").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                            Text("No review thread loaded").font(FolioTheme.heading(18))
                            Text("Search by title or paste an OpenReview link to read public reviews beside this paper.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    ForEach(model.candidates) { candidate in
                        Button { model.fetch(candidate.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(candidate.title).font(.headline).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Text(candidate.venue.isEmpty ? candidate.id : candidate.venue).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).folioCard(padding: 12)
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                    if let forum = model.saved?.forum { forumContent(forum) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
            }.scrollIndicators(.automatic)
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FolioTheme.panelRight)
        .onAppear { if title.isEmpty { title = paper.title }; model.load(root: workspace.repository?.root, record: paper) }
        .environment(\.openURL, OpenURLAction { url in url.scheme?.lowercased() == "https" && url.host?.lowercased() == "openreview.net" ? .systemAction : .discarded })
    }

    private func forumContent(_ forum: ReviewForum) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Link(forum.title.isEmpty ? forum.id : forum.title, destination: forum.url).font(FolioTheme.heading(20)).fixedSize(horizontal: false, vertical: true)
            Text([forum.venue, forum.decision].filter { !$0.isEmpty }.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
            ForEach(forum.notes.filter { $0.kind == "review" }) { note in
                let scoreText = note.scores.map { "\($0.name): \($0.text)" }.joined(separator: " · ")
                if !scoreText.isEmpty { Text("\(note.author) · \(scoreText)").font(.caption).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Picker("Analyze with", selection: $providerValue) { ForEach(AssistantProvider.allCases) { item in Text(item.name).tag(item.rawValue) } }
                    .disabled(model.busy)
                Button(model.saved?.analysis == nil ? "Analyze reviews" : "Analyze again") { model.analyze(provider: provider) }
                    .buttonStyle(.borderedProminent).disabled(model.busy || !forum.hasReviews)
            }
            Text("Analyze shares paper and review excerpts with \(provider.name). Check assessments against the cited sources.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if forum.limited { Text("This thread exceeds the extraction limit. Some review text is omitted.").font(.caption).foregroundStyle(.secondary) }
            if let result = model.saved?.analysis {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review summary").font(FolioTheme.heading(20))
                    Text(result.summary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text("Sources: " + result.summaryNoteIDs.compactMap { id in forum.notes.first { $0.id == id }.map { "\($0.author) (\($0.kind))" } }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    Text("\(result.concerns.count) concerns · \(result.concerns.filter { $0.severity == "major" }.count) major · \(result.model)").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(result.concerns) { concern in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(concern.severity.capitalized) · \(concern.type.replacingOccurrences(of: "_", with: " "))\(concern.inMetaReview ? " · Meta-review" : "")").font(.caption.weight(.semibold)).foregroundStyle(FolioTheme.accent)
                        Text(concern.title).font(FolioTheme.heading(18)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text(concern.summary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text("Raised by " + concern.raisedBy.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(concern.quotes.enumerated()), id: \.offset) { _, quote in
                            VStack(alignment: .leading, spacing: 5) { Text(quote.author).font(.caption.weight(.semibold)); Text("“\(quote.text)”").font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                                .frame(maxWidth: .infinity, alignment: .leading).folioWell()
                        }
                        Text("Authors: " + concern.authorResponse.replacingOccurrences(of: "_", with: " ") + (concern.responseSummary.isEmpty ? "" : ". " + concern.responseSummary)).font(.callout).fixedSize(horizontal: false, vertical: true)
                        if concern.sources.isEmpty { Text(concern.missing ? "Concern about missing evidence; no exact paper passage was matched." : "No exact supplied paper passage was matched.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(concern.sources) { source in
                            VStack(alignment: .leading, spacing: 5) {
                                Button("Read contested passage · p. \(source.page)") { workspace.go(to: source.page) }.buttonStyle(.link)
                                    .accessibilityLabel("Go to page \(source.page)")
                                Text(source.text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).folioCard(padding: 14)
                }
                Text("AI concerns reflect the supplied excerpts. Paper and review coverage are bounded; check the original thread and cited pages.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Review thread (\(forum.notes.count) notes)") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(forum.notes) { note in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(note.author) · \(note.kind.capitalized)").font(.headline)
                            ForEach(Array(note.scores.enumerated()), id: \.offset) { _, field in Text("\(field.name): \(field.text)").font(.caption) }
                            ForEach(Array(note.sections.enumerated()), id: \.offset) { _, field in VStack(alignment: .leading, spacing: 4) { Text(field.name).font(.callout.weight(.semibold)); Text(field.text).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) } }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.top, 10)
            }
        }
    }
}

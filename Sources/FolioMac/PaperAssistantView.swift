import SwiftUI
import PDFKit
import FolioCore

/// Thread-safe accumulator so provider callbacks never race the main actor; the model drains it on a short timer.
final class AssistantStreamBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func append(_ text: String) { lock.lock(); value += text; lock.unlock() }
    func take() -> String? { lock.lock(); defer { lock.unlock() }; guard !value.isEmpty else { return nil }; defer { value = "" }; return value }
}

struct AssistantAttempt: Equatable {
    let question: String
    let selection: String?
    let page: Int
    let simplified: Bool
}

@MainActor
final class PaperAssistantModel: ObservableObject {
    @Published var snapshot: AssistantSnapshot?
    @Published var threads: AssistantThreads?
    @Published var paper: AssistantPaper?
    @Published var error: String?
    @Published var busy = false
    @Published var progress = ""
    @Published var streaming = ""
    @Published var pendingQuestion: String?
    @Published var retry: AssistantAttempt?
    @Published var insights: PaperInsights?
    private var repository: AssistantRepository?
    private var threadRepository: AssistantThreadRepository?
    private var task: Task<Void, Never>?
    private var loaded = false
    private let service: AssistantService
    init(service: AssistantService = AssistantService()) { self.service = service }

    var activeTurns: [AssistantTurn] { threads?.active?.turns ?? [] }

    /// Paper extraction is independent of saved conversations and never writes assistant state.
    static func readPaper(root: URL?, record: PaperRecord) throws -> AssistantPaper {
        guard let root else { throw AssistantError.message("The local library is unavailable.") }
        let url = root.appendingPathComponent("Documents").appendingPathComponent(record.id.uuidString).appendingPathExtension("pdf")
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount == record.pageCount else {
            throw AssistantError.message("This managed PDF could not be read.")
        }
        return try AssistantPaper(title: record.title, pages: (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" })
    }

    func load(root: URL?, record: PaperRecord) {
        guard !loaded else { return }; loaded = true
        guard let root else { error = "The local library is unavailable."; return }
        do {
            let paper = try Self.readPaper(root: root, record: record)
            let repository = AssistantRepository(root: root, paperID: record.id, paper: paper)
            let saved = try repository.load()
            let threadRepository = AssistantThreadRepository(root: root, paperID: record.id, fingerprint: paper.fingerprint)
            let threads = try threadRepository.load(legacyTurns: saved.turns)
            self.paper = paper; self.repository = repository; self.threadRepository = threadRepository; snapshot = saved; self.threads = threads
        } catch { self.error = error.localizedDescription }
    }

    // MARK: Threads
    @discardableResult private func persist(_ next: AssistantThreads) -> Bool {
        do {
            guard let threadRepository else { throw AssistantError.invalidData }
            try threadRepository.save(next); threads = next; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func newThread() { guard !busy, var next = threads else { return }; next.newThread(); threads = next; error = nil; retry = nil }
    func select(_ id: UUID) { guard !busy, var next = threads, next.threads.contains(where: { $0.id == id }) else { return }; next.activeID = id; threads = next; error = nil; retry = nil }
    func rename(_ id: UUID, to title: String) { guard var next = threads else { return }; next.rename(id, to: title); persist(next) }
    func delete(_ id: UUID) { guard !busy, var next = threads else { return }; next.delete(id); if persist(next) { retry = nil } }

    // MARK: Conversation
    func ask(_ question: String, provider: AssistantProvider, page: Int, selection: String?, simplified: Bool) {
        guard !busy, let paper, var current = threads else { return }
        if current.active == nil { current.newThread(); threads = current }
        let attempt = AssistantAttempt(question: question, selection: selection, page: page, simplified: simplified)
        let history = current.active?.turns ?? []
        let buffer = AssistantStreamBuffer()
        streaming = ""; pendingQuestion = question; retry = nil
        begin(provider == .claude ? "Waiting for Claude…" : "Codex is working on this. Its answer appears when it finishes…", onStop: { self.retry = attempt }) {
            let poll = Task { @MainActor in
                while !Task.isCancelled { try? await Task.sleep(nanoseconds: 60_000_000); if let chunk = buffer.take() { self.streaming += chunk; self.progress = "Writing…" } }
            }
            defer { poll.cancel() }
            let answer = try await self.service.answer(question: question, paper: paper, history: history, provider: provider, page: page, selection: selection, simplified: simplified, onText: { buffer.append($0) })
            try Task.checkCancellation()
            guard var next = self.threads else { return }
            let stored = "[Reading page \(page) of \(paper.pageCount)]\n" + (selection.map { "Selected passage (p. \(page)):\n\(String($0.prefix(12_000)))\n\n\(question)" } ?? question)
            next.append(question: stored, answer: answer, titleSource: question)
            try self.threadRepository?.save(next); self.threads = next
        }
    }
    func generateOverview(provider: AssistantProvider) {
        guard !busy, let paper, let snapshot else { return }
        begin("Reading the paper for a supported overview…") {
            let overview = try await self.service.overview(paper: paper, provider: provider)
            try Task.checkCancellation()
            var next = snapshot; next.overview = overview
            try self.repository?.save(next); self.snapshot = next
        }
    }
    /// Local and offline: extractive key sentences and keywords from the PDF's own text layer.
    func loadInsights() {
        guard insights == nil, let pages = paper?.lookupPages else { return }
        Task { let result = await Task.detached(priority: .userInitiated) { InsightAnalysis.analyze(pages: pages) }.value; self.insights = result }
    }
    private func begin(_ progress: String, onStop: (() -> Void)? = nil, operation: @escaping () async throws -> Void) {
        busy = true; error = nil; self.progress = progress
        task = Task {
            defer { self.busy = false; self.task = nil; self.progress = ""; self.streaming = ""; self.pendingQuestion = nil }
            do { try await operation() }
            catch is CancellationError { onStop?() }
            catch { if Task.isCancelled { onStop?() } else { self.error = error.localizedDescription; onStop?() } }
        }
    }
    func cancel() { task?.cancel() }
}

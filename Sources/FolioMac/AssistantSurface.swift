import Foundation
import FolioCore

enum PaperSurfaceKind: String { case assistant, overview, reviews, concepts }

extension Workspace {
    /// Opens an AI section in the reader's right panel, opening the paper first when needed (e.g. from the library).
    /// `prompt`/`selection` prefill Ask; `autoSend` is used only by explicit one-click actions such as Explain.
    func present(_ kind: PaperSurfaceKind, for paper: PaperRecord? = nil, selection: String? = nil, page: Int? = nil, prompt: String? = nil, autoSend: Bool = false) {
        guard let paper = paper ?? activePaper else { return }
        if kind == .overview { showInsights(for: paper); return }
        guard finishEditorIfNeeded() else { return }
        if activeID != paper.id || document == nil { open(paper) } else { reading = true }
        guard activeID == paper.id else { return }
        ensureAIStore()
        switch kind {
        case .assistant: panel = .ask
        case .overview: return
        case .reviews: panel = .reviews
        case .concepts: panel = .map
        }
        inspector = true
        if kind == .assistant, selection != nil || prompt != nil {
            askRequest = AskRequest(selection: selection, page: page ?? self.page, prompt: prompt ?? "", autoSend: autoSend)
        }
    }
    /// Ask about (or, with `explain`, immediately explain) the reader's current text selection.
    func askAboutSelection(explain: Bool) {
        let text = pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = (text?.isEmpty == false) ? text : nil
        let selectionPage = pdfView?.currentSelection?.pages.first.flatMap { document?.index(for: $0) }.map { $0 + 1 } ?? page
        present(.assistant, selection: selected, page: selectionPage,
                prompt: explain && selected != nil ? "Explain this selected passage in plain language, including its role in the paper." : nil,
                autoSend: explain && selected != nil)
    }
}

// Insights is a library destination. Browsing it never changes the open PDF or reading position.
extension Workspace {
    func navigate(to section: LibrarySection) {
        guard finishEditorIfNeeded() else { return }
        self.section = section
        reading = false
    }
    func showInsights(for paper: PaperRecord) {
        guard finishEditorIfNeeded() else { return }
        insightsPaperID = paper.id
        section = .insights
        reading = false
    }
}

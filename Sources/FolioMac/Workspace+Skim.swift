import AppKit
import PDFKit
import FolioCore

struct SkimMark {
    let page: PDFPage
    let facet: SkimFacet
    let rects: [CGRect]
}

extension SkimFacet {
    var color: NSColor {
        switch self {
        case .objective: .systemOrange
        case .method: .systemBlue
        case .result: .systemGreen
        }
    }
}

extension Workspace {
    func toggleSkim() {
        if skimEnabled { clearSkim(); return }
        guard let document, reading else { return }
        skimEnabled = true; skimLoading = true; skimError = nil
        let request = UUID(); skimRequest = request
        skimTask = Task { [weak self, weak document] in
            guard let self, let document else { return }
            do {
                // PDFKit stays on the UI actor. Yield between pages so Cancel/document switches can run.
                var pages: [String] = []
                for index in 0..<document.pageCount {
                    try Task.checkCancellation()
                    pages.append(document.page(at: index)?.string ?? "")
                    await Task.yield()
                }
                let predictions = try await SkimClassifier.shared.classifyPages(pages)
                var marks: [SkimMark] = []
                for prediction in predictions {
                    try Task.checkCancellation()
                    let sentence = prediction.sentence
                    guard let page = document.page(at: sentence.page - 1),
                          let selection = page.selection(for: NSRange(location: sentence.location, length: sentence.length)) else { continue }
                    let rects = selection.selectionsByLine().compactMap { PDFEditing.contained($0.bounds(for: page), in: page.bounds(for: .cropBox)) }
                    if !rects.isEmpty { marks.append(SkimMark(page: page, facet: prediction.facet, rects: rects)) }
                    if marks.count.isMultiple(of: 20) { await Task.yield() }
                }
                guard self.skimRequest == request, self.document === document, self.skimEnabled else { return }
                self.skimMarks = marks; self.skimLoading = false; self.skimTask = nil
            } catch is CancellationError {
                // The owner already cleared state; an old job must never change a newer document.
            } catch {
                guard self.skimRequest == request, self.document === document else { return }
                self.skimLoading = false; self.skimError = error.localizedDescription; self.skimTask = nil
            }
        }
    }

    func clearSkim() {
        skimRequest = UUID(); skimTask?.cancel(); skimTask = nil
        skimEnabled = false; skimLoading = false; skimMarks = []; skimError = nil
    }

    func toggleSkimFacet(_ facet: SkimFacet) {
        if skimFacets.contains(facet) { skimFacets.remove(facet) } else { skimFacets.insert(facet) }
    }
}

import AppKit
import FolioCore
import PDFKit

struct WritingPageOp {
    let page: PDFPage
    let index: Int
    let depth: Int
}

extension Workspace {
    private var imageStore: NoteImageStore? { repository.map { NoteImageStore(root: $0.root) } }
    private var draftStore: NoteDraftStore? { repository.map { NoteDraftStore(root: $0.root) } }

    // MARK: Note images

    func addNoteImage(_ image: NSImage) -> String? {
        guard let id = activeID, let store = imageStore,
              let png = NoteImageStore.png(from: image), png.count <= 20_000_000 else {
            errorMessage = "Choose an image smaller than 20 MB."; return nil
        }
        do { return try store.save(png, paper: id) }
        catch { errorMessage = "Could not store the image. \(error.localizedDescription)"; return nil }
    }
    func noteImage(_ name: String) -> NSImage? {
        if let id = activeID, let data = imageStore?.data(name, paper: id) { return NSImage(data: data) }
        for note in notes {
            if let encoded = StudyCopy.embeddedImages(in: note.annotation)[name], encoded.count <= 28_000_000, let data = Data(base64Encoded: encoded) { return NSImage(data: data) }
        }
        return nil
    }

    // MARK: Editing notes in place

    @discardableResult
    func updateNote(_ note: PaperNote, body: String, images: [String]) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return false }
        guard let page = note.annotation.page, let copy = PDFEditing.copy(note.annotation) else { return false }
        guard trimmed != note.body || images != note.images else { return true }
        copy.contents = trimmed
        copy.modificationDate = Date()
        copy.setValue(images.joined(separator: ","), forAnnotationKey: PDFNotes.imagesKey)
        return replaceAnnotation(note.annotation, with: copy, on: page, name: "Edit Note")
    }

    // MARK: Draft recovery

    func persistNoteDraft(_ draft: AnnotationDraft, text: String) {
        guard draft.original == nil, let id = activeID, let store = draftStore, let index = document?.index(for: draft.page), index != NSNotFound else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (draft.kind != .text || pendingEditorImages.isEmpty) { store.clear(paper: id); return }
        store.save(NoteDraftRecord(page: index + 1, bounds: draft.bounds, isFreeText: draft.kind == .freeText,
                                   text: text, quote: draft.quote, images: pendingEditorImages), paper: id)
    }
    func clearNoteDraft() { if let id = activeID { draftStore?.clear(paper: id) } }
    func restoreNoteDraft() {
        guard editor == nil, let id = activeID, let document, let record = draftStore?.load(paper: id),
              let page = document.page(at: record.page - 1),
              let bounds = PDFEditing.contained(record.bounds, in: page.bounds(for: .cropBox)) else { return }
        go(to: record.page)
        editor = AnnotationDraft(page: page, bounds: bounds, kind: record.isFreeText ? .freeText : .text,
                                 text: record.text, quote: record.quote, selection: nil, images: record.images)
    }

    // MARK: Writing pages

    /// Inserts a blank ruled page after `number` (nil = end of the managed copy).
    func insertWritingPage(after number: Int?) {
        guard finishEditorIfNeeded(), let document else { return }
        let index = min(max(number ?? document.pageCount, 0), document.pageCount)
        let reference = document.page(at: max(0, min(index - 1, document.pageCount - 1)))?.bounds(for: .mediaBox).size ?? CGSize(width: 612, height: 792)
        guard let blank = WritingPages.blankPage(size: reference) else { errorMessage = "Could not create a writing page."; return }
        document.insert(blank, at: index)
        do { try savePageStructure(document, first: index + 1, delta: 1, goTo: index + 1) }
        catch {
            document.removePage(at: index)
            errorMessage = "Could not add the writing page. Your previous PDF was kept. \(error.localizedDescription)"; return
        }
        editHistory?.discardRedo()
        writingUndo.append(WritingPageOp(page: blank, index: index, depth: editHistory?.depth ?? 0)); writingRedo = []
        afterPageStructureChange(goTo: index + 1)
    }

    func undoWritingPage() -> Bool {
        guard let op = writingUndo.last, op.depth == (editHistory?.depth ?? 0), let document,
              document.index(for: op.page) == op.index else { return false }
        document.removePage(at: op.index)
        do { try savePageStructure(document, first: op.index + 1, delta: -1, goTo: min(op.index, document.pageCount)) }
        catch { document.insert(op.page, at: op.index); errorMessage = "Could not undo. \(error.localizedDescription)"; return true }
        writingUndo.removeLast(); writingRedo.append(op)
        afterPageStructureChange(goTo: min(op.index, document.pageCount))
        return true
    }

    func redoWritingPage() -> Bool {
        guard let op = writingRedo.last, op.depth == (editHistory?.depth ?? 0), let document,
              op.index <= document.pageCount else { return false }
        document.insert(op.page, at: op.index)
        do { try savePageStructure(document, first: op.index + 1, delta: 1, goTo: op.index + 1) }
        catch { document.removePage(at: op.index); errorMessage = "Could not redo. \(error.localizedDescription)"; return true }
        writingRedo.removeLast(); writingUndo.append(op)
        afterPageStructureChange(goTo: op.index + 1)
        return true
    }

    private func afterPageStructureChange(goTo number: Int) {
        clearSkim()
        selectionInsight = nil; askRequest = nil
        aiStore?.cancelAll(); aiStore = nil
        ensureAIStore()
        reader.pageStructureDidChange()
        revision += 1
        pdfView?.layoutDocumentView()
        go(to: max(1, number))
    }
}

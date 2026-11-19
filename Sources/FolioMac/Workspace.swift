import AppKit
import Combine
import CoreText
import FolioCore
import PDFKit
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable, Identifiable {
    case all = "All PDFs", opened = "Recent", notes = "Notes", starred = "Starred pages", insights = "Insights", conversations = "Conversations"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "books.vertical"
        case .opened: "clock"
        case .notes: "note.text"
        case .starred: "star"
        case .insights: "lightbulb"
        case .conversations: "bubble.left.and.bubble.right"
        }
    }
}

@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var folders: [String] = []
    @Published private(set) var selectedFolder: String?
    @Published private(set) var papers: [PaperRecord] = []
    @Published private(set) var document: PDFDocument? { didSet { cachedNotes = nil; documentSessionID = UUID(); reader.documentDidChange() } }
    private(set) var documentSessionID = UUID()
    @Published private(set) var activeID: UUID?
    @Published var reading = false {
        didSet { if !reading { insightsMode = false; selectionInsight = nil; clearSkim() } }
    }
    @Published var insightsMode = false
    @Published var selectionInsight: SelectionInsightRequest?
    @Published var skimEnabled = false
    @Published var skimLoading = false
    @Published var skimError: String?
    @Published var skimMarks: [SkimMark] = []
    @Published var skimFacets = Set(SkimFacet.allCases)
    var skimTask: Task<Void, Never>?
    var skimRequest = UUID()
    @Published var section: LibrarySection = .all
    @Published var insightsPaperID: UUID?
    @Published var passageHistory: [PDFDestination] = []
    @Published var page = 1
    @Published var inspector = false
    @Published var showDocumentNavigation = false
    @Published var tool: PDFTool = .select
    @Published var markColor = AnnotationPalette.stored() { didSet { AnnotationPalette.store(markColor) } }
    @Published var fontSize: CGFloat = 16
    @Published var selectedAnnotation: PDFAnnotation?
    @Published var editor: AnnotationDraft? {
        didSet {
            if oldValue?.id != editor?.id {
                oldValue?.original?.shouldDisplay = true // inline text editing hides the annotation's own drawing
                pendingEditorText = editor?.text ?? ""
                pendingEditorSize = editor?.original?.font?.pointSize ?? fontSize
                pendingEditorImages = editor?.original.map(PDFNotes.images) ?? editor?.images ?? []
                if editor == nil { clearNoteDraft() }
            }
        }
    }
    /// The on-page text editor for the active free-text draft (owned by the canvas coordinator).
    weak var inlineText: InlineTextController?
    var pendingEditorText = ""
    var pendingEditorSize: CGFloat = 16
    var pendingEditorImages: [String] = []
    var writingUndo: [WritingPageOp] = []
    var writingRedo: [WritingPageOp] = []
    @Published var saveFailed = false
    @Published var pendingWriting: (page: PDFPage, text: String)?
    @Published var showWriting = false
    @Published var showFind = false
    /// Right panel section and the open paper's AI state (see ReaderPanel.swift).
    @Published var panel: ReaderPanel = .notes
    @Published var aiStore: PaperAIStore?
    @Published var askRequest: AskRequest?
    @Published var errorMessage: String?
    @Published var libraryQuery = ""
    @Published var showArxivImport = false
    @Published var revision = 0 { didSet { cachedNotes = nil; reader.contentDidChange() } }
    weak var pdfView: PDFView?
    private(set) lazy var reader = ReaderState(workspace: self)
    private(set) var editHistory: PDFEditHistory?
    private(set) var repository: LibraryRepository?

    var recentPapers: [PaperRecord] {
        papers.filter { $0.lastVisit != nil }.sorted {
            if $0.lastVisit != $1.lastVisit { return $0.lastVisit! > $1.lastVisit! }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    var libraryPapers: [PaperRecord] {
        if section == .opened { return recentPapers }
        if section == .all, let selectedFolder { return papers.filter { $0.folderPath == selectedFolder || ($0.folderPath?.hasPrefix(selectedFolder.hasSuffix("/") ? selectedFolder : selectedFolder + "/") ?? false) } }
        return papers
    }

    var activePaper: PaperRecord? { papers.first { $0.id == activeID } }
    // PDFKit page/annotation traversal is expensive during unrelated SwiftUI updates.
    // Cache only the active document; edits and rollback replace annotation identities.
    private var cachedNotes: [PaperNote]?
    var notes: [PaperNote] {
        if let cachedNotes { return cachedNotes }
        let notes = document.map(PDFNotes.read) ?? []
        cachedNotes = notes
        return notes
    }
    var isStarred: Bool { activePaper?.starredPages.contains(page) == true }

    init(libraryRoot: URL? = nil) {
        do {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            // The launch argument isolates disposable UI verification from the real library.
            let arguments = ProcessInfo.processInfo.arguments
            let root: URL
            if let libraryRoot { root = libraryRoot }
            else if let index = arguments.firstIndex(of: "--library-path"), arguments.count > index + 1 {
                root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            } else { root = base.appendingPathComponent("FolioMac", isDirectory: true) }
            let repository = try LibraryRepository(root: root)
            papers = try repository.load()
            folders = try repository.loadFolders()
            self.repository = repository
        } catch {
            // No replacement manifest is written after a failed load.
            errorMessage = "Could not open the local library. \(error.localizedDescription)"
        }
    }

    func chooseFolder() {
        guard finishEditorIfNeeded(), repository != nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Open PDFs recursively, including subfolders, as private local copies. Reopen it to add new PDFs."
        if panel.runModal() == .OK, let url = panel.url { openFolder(url) }
    }

    func selectFolder(_ path: String) {
        guard finishEditorIfNeeded() else { return }
        navigate(to: .all)
        selectedFolder = path
        libraryQuery = ""
    }

    func clearFolderSelection() { selectedFolder = nil }

    /// Explicit folder scans only; previously imported files retain their managed edits and identity.
    func openFolder(_ url: URL) {
        guard finishEditorIfNeeded(), let repository else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let path = url.standardizedFileURL.path
        do {
            var scanError: Error?
            guard let scan = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in scanError = error; return true }) else { return }
            var urls: [URL] = []
            var discovered = Set([path])
            for case let source as URL in scan {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
                if values.isSymbolicLink == true { scan.skipDescendants(); continue }
                if values.isDirectory == true { discovered.insert(source.standardizedFileURL.path) }
                if values.isRegularFile == true && source.pathExtension.lowercased() == "pdf" { urls.append(source) }
            }
            urls.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            let next = Set(folders).union(discovered).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            try repository.save(papers, folders: next)
            folders = next
            var failures: [String] = scanError.map { [$0.localizedDescription] } ?? []
            var importedPaths = Set(papers.compactMap { record -> String? in
                guard let folder = record.folderPath, let source = record.sourcePath else { return nil }
                return folder + "\0" + source
            })
            for source in urls {
                let path = source.deletingLastPathComponent().standardizedFileURL.path
                let identity = path + "\0" + source.standardizedFileURL.path
                if importedPaths.contains(identity) { continue }
                do {
                    papers.append(try repository.importPDF(from: source, existing: papers, folderPath: path))
                    importedPaths.insert(identity)
                }
                catch { failures.append("\(source.lastPathComponent): \(error.localizedDescription)") }
            }
            selectFolder(path)
            if !failures.isEmpty { errorMessage = "Some PDFs could not be imported.\n" + failures.joined(separator: "\n") }
        } catch { errorMessage = "Could not open this folder. \(error.localizedDescription)" }
    }

    func choosePDF() {
        guard finishEditorIfNeeded(), repository != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Folio keeps a private local copy. Your original stays untouched."
        if panel.runModal() == .OK { importPDFs(panel.urls) }
    }

    /// Imports several PDFs as managed copies. A single file opens in the reader; several stay in the library.
    func importPDFs(_ urls: [URL], title: String? = nil) {
        let pdfs = urls.filter { $0.isFileURL }
        guard let repository, !pdfs.isEmpty else { return }
        if pdfs.count == 1 { importPDF(pdfs[0], title: title); return }
        var failures: [String] = []
        for url in pdfs {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { papers.append(try repository.importPDF(from: url, existing: papers)) }
            catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        navigate(to: .all)
        if !failures.isEmpty { errorMessage = "Some files were not imported.\n" + failures.joined(separator: "\n") }
    }

    func renamePaper(_ paper: PaperRecord, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let repository, let index = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        var next = papers
        next[index].title = trimmed
        do { try repository.save(next); papers = next }
        catch { errorMessage = "Could not rename the paper. \(error.localizedDescription)" }
    }

    /// Removes the library entry and Folio's managed copy. The original file you imported is never touched.
    func removePaper(_ paper: PaperRecord) {
        guard let repository else { return }
        if activeID == paper.id, !finishEditorIfNeeded() { return }
        do {
            let next = try repository.remove(paper.id, from: papers)
            if aiStore?.paperID == paper.id { aiStore?.cancelAll(); aiStore = nil }
            if activeID == paper.id {
                editor = nil // clear the old paper's recovery draft before clearing its identity
                pendingWriting = nil; askRequest = nil; passageHistory = []
                writingUndo = []; writingRedo = []
                showWriting = false; saveFailed = false; tool = .select; page = 1
                reading = false; document = nil; activeID = nil; editHistory = nil; selectedAnnotation = nil
            }
            if insightsPaperID == paper.id { insightsPaperID = nil }
            papers = next
        } catch { errorMessage = "Could not remove the paper. \(error.localizedDescription)" }
    }

    func revealInFinder(_ paper: PaperRecord) {
        guard let repository else { return }
        NSWorkspace.shared.activateFileViewerSelecting([repository.documentURL(for: paper.id)])
    }

    func importPDF(_ url: URL, title: String? = nil) {
        guard let repository else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let record = try repository.importPDF(from: url, existing: papers, title: title)
            papers.append(record)
            open(record)
        } catch { errorMessage = error.localizedDescription }
    }

    func open(_ paper: PaperRecord, at target: Int? = nil) {
        guard finishEditorIfNeeded(), let repository else { return }
        let paper = papers.first { $0.id == paper.id } ?? paper
        // Detach PDFKit's lazy file backing before atomically replacing the managed URL.
        // Keep the open document independent of subsequent managed-file replacements.
        guard let bytes = try? Data(contentsOf: repository.documentURL(for: paper.id)),
              let next = PDFDocument(data: bytes), !next.isLocked, next.pageCount > 0 else {
            errorMessage = "This managed PDF could not be opened. Your library entry was kept."
            return
        }
        PDFEditing.prepare(next)
        aiStore?.cancelAll(); aiStore = nil; askRequest = nil
        clearSkim()
        selectedAnnotation = nil
        editor = nil
        tool = .select
        saveFailed = false
        editHistory = PDFEditHistory(document: next) { [weak self, repository, id = paper.id] saved in
            if let reader = self?.reader { try reader.withOriginalRotation(saved) { try repository.saveDocument(saved, for: id) } }
            else { try repository.saveDocument(saved, for: id) }
        }
        insightsMode = false; selectionInsight = nil
        activeID = paper.id
        document = next
        passageHistory = []
        page = min(max(target ?? paper.currentPage, 1), next.pageCount)
        writingUndo = []; writingRedo = []
        reading = true
        updateActive { $0.lastOpened = Date(); $0.visitedAt = $0.lastOpened; $0.currentPage = page }
        restoreNoteDraft()
    }

    func showLibrary() { if finishEditorIfNeeded() { reading = false } }

    func go(to target: Int) {
        guard finishEditorIfNeeded() else { return }
        guard let document else { return }
        let index = min(max(target, 1), document.pageCount) - 1
        guard let pdfPage = document.page(at: index) else { return }
        rememberPassage()
        pdfView?.go(to: pdfPage)
        changedPage(index + 1)
    }

    func rememberPassage() {
        guard let destination = pdfView?.currentDestination else { return }
        if let last = passageHistory.last, last.page === destination.page, abs(last.point.x - destination.point.x) < 1, abs(last.point.y - destination.point.y) < 1 { return }
        passageHistory.append(destination)
        if passageHistory.count > 80 { passageHistory.removeFirst() }
    }
    func returnToPassage() {
        guard finishEditorIfNeeded(), let document else { return }
        while let destination = passageHistory.popLast() {
            guard let page = destination.page, document.index(for: page) != NSNotFound else { continue }
            pdfView?.go(to: destination)
            changedPage(document.index(for: page) + 1)
            return
        }
    }

    @discardableResult func flushWriting() -> Bool {
        guard let pending = pendingWriting else { return true }
        guard let document, document.index(for: pending.page) != NSNotFound else { return false }
        let old = StudyCopy.writing(on: pending.page)
        if (old?.contents ?? "") == pending.text { pendingWriting = nil; return true }
        var add: [(PDFPage, PDFAnnotation)] = []
        if !pending.text.isEmpty {
            let note = PDFAnnotation(bounds: CGRect(x: 8, y: 8, width: 16, height: 16), forType: .text, withProperties: nil)
            note.contents = pending.text
            note.setValue("1", forAnnotationKey: StudyCopy.writingKey)
            note.shouldDisplay = false; note.shouldPrint = false
            add = [(pending.page, note)]
        }
        guard apply(add: add, remove: old.map { [(pending.page, $0)] } ?? [], name: "Edit Writing Below Page") else { return false }
        pendingWriting = nil
        return true
    }

    func toggleWriting() {
        guard !showWriting || flushWriting() else { return }
        showWriting.toggle()
    }

    func changedPage(_ number: Int) {
        guard let document, (1...document.pageCount).contains(number), number != page else { return }
        guard flushWriting() else {
            if let original = document.page(at: page - 1) { pdfView?.go(to: original) }
            return
        }
        page = number
        updateActive { $0.currentPage = number }
    }

    func toggleStar() {
        let current = page
        updateActive {
            if $0.starredPages.contains(current) { $0.starredPages.remove(current) }
            else { $0.starredPages.insert(current) }
        }
    }

    func updateActive(_ edit: (inout PaperRecord) -> Void) {
        guard let id = activeID, let index = papers.firstIndex(where: { $0.id == id }), let repository else { return }
        var next = papers
        edit(&next[index])
        do { try repository.save(next); papers = next }
        catch { errorMessage = "Could not save library metadata. \(error.localizedDescription)" }
    }

    /// Metadata and PDF must describe the same structure before publishing the new state.
    func savePageStructure(_ document: PDFDocument, first: Int, delta: Int, goTo target: Int) throws {
        guard let repository, let id = activeID, let index = papers.firstIndex(where: { $0.id == id }),
              document === self.document else { throw LibraryRepository.RepositoryError.invalidRecord }
        var next = papers
        next[index].pageCount = document.pageCount
        next[index].currentPage = min(max(1, target), document.pageCount)
        next[index].starredPages = Set(next[index].starredPages.compactMap { n in
            if delta > 0 { return n >= first ? n + 1 : n }
            if n == first { return nil }
            return n > first ? n - 1 : n
        })
        try reader.withOriginalRotation(document) { try repository.saveStructure(document, for: id, papers: next) }
        papers = next
    }

    var selectedColor: NSColor { AnnotationPalette.fill(markColor) }
    var textInk: NSColor { AnnotationPalette.ink(markColor) }
    var canUndo: Bool { pendingWriting != nil || editHistory?.canUndo == true || !writingUndo.isEmpty }
    var canRedo: Bool { editHistory?.canRedo == true || !writingRedo.isEmpty }

    func chooseTool(_ next: PDFTool) {
        guard finishEditorIfNeeded() else { return }
        selectedAnnotation = nil
        insightsMode = false; selectionInsight = nil
        tool = next
        if next == .highlight || next == .underline { markSelection(next == .highlight ? .highlight : .underline) }
        if next == .note, let selection = pdfView?.currentSelection, !(selection.string ?? "").isEmpty {
            beginNote(selection: selection)
        }
        pdfView?.window?.makeFirstResponder(pdfView)
    }

    func markSelection(_ type: PDFAnnotationSubtype) {
        guard let selection = pdfView?.currentSelection, let document else { return }
        let additions = PDFEditing.marks(for: selection, in: document, type: type, color: type == .underline ? AnnotationPalette.underline(markColor) : selectedColor)
        guard !additions.isEmpty else { return }
        let replacement = PDFEditing.replacingHighlights(additions)
        if apply(add: replacement.add, remove: replacement.remove, name: type == .highlight ? "Highlight" : "Underline") {
            pdfView?.clearSelection()
        }
    }

    func select(_ annotation: PDFAnnotation?) { selectedAnnotation = annotation }

    func recolor(_ color: String) {
        markColor = color
        replaceSelected("Change Color") { annotation in
            if annotation.type == "FreeText" { annotation.fontColor = self.textInk }
            else if annotation.type == "Underline" { annotation.color = AnnotationPalette.underline(color) }
            else { annotation.color = self.selectedColor }
        }
    }

    func resizeFont(_ size: CGFloat) {
        fontSize = size
        guard selectedAnnotation?.type == "FreeText" else { return }
        replaceSelected("Text Size") { annotation in
            annotation.font = PDFEditing.textFont(size: size, bold: PDFEditing.isBold(annotation.font))
            annotation.bounds = self.fittedText(annotation.contents ?? "", font: annotation.font!, bounds: annotation.bounds, page: annotation.page ?? self.selectedAnnotation!.page!)
        }
    }

    private func replaceSelected(_ name: String, edit: (PDFAnnotation) -> Void) {
        prepareAnnotationEdit()
        guard let selected = selectedAnnotation, let document else { return }
        let members = PDFEditing.members(of: selected, in: document)
        var additions: [(PDFPage, PDFAnnotation)] = []
        for (page, old) in members {
            guard let copy = PDFEditing.copy(old) else { return }
            edit(copy)
            if copy.type == "FreeText" { PDFEditing.recordTextStyle(copy) }
            additions.append((page, copy))
        }
        let selectedIndex = members.firstIndex(where: { $0.1 === selected }) ?? 0
        if apply(add: additions, remove: members, name: name) {
            selectedAnnotation = additions.indices.contains(selectedIndex) ? additions[selectedIndex].1 : nil
        }
    }

    func deleteSelection() {
        guard let annotation = selectedAnnotation else { return }
        erase([annotation])
    }

    func erase(_ annotations: [PDFAnnotation]) {
        guard let document else { return }
        var seen = Set<ObjectIdentifier>()
        let removals = annotations.flatMap { PDFEditing.members(of: $0, in: document) }.filter { seen.insert(ObjectIdentifier($0.1)).inserted }
        guard !removals.isEmpty else { return }
        if apply(add: [], remove: removals, name: "Erase Annotations") { selectedAnnotation = nil }
    }

    func move(_ annotation: PDFAnnotation, to bounds: CGRect) {
        prepareAnnotationEdit()
        guard let page = annotation.page, ["Text", "FreeText", "Stamp"].contains(annotation.type ?? ""),
              let rect = PDFEditing.contained(bounds, in: page.bounds(for: .cropBox)), rect != annotation.bounds,
              let copy = PDFEditing.copy(annotation) else { return }
        copy.bounds = annotation.type == "FreeText" ? fittedText(annotation.contents ?? "", font: annotation.font ?? .systemFont(ofSize: fontSize), bounds: rect, page: page) : rect
        if apply(add: [(page, copy)], remove: [(page, annotation)], name: "Move Annotation") { selectedAnnotation = copy }
    }

    func beginNote(selection: PDFSelection? = nil, on page: PDFPage? = nil, at point: CGPoint? = nil) {
        guard finishEditorIfNeeded(), let document, let target = page ?? selection?.pages.first ?? document.page(at: self.page - 1), target.document === document else { return }
        let box = target.bounds(for: .cropBox)
        let point = point ?? selection.map { CGPoint(x: $0.bounds(for: target).minX, y: $0.bounds(for: target).maxY) } ?? CGPoint(x: box.minX + 24, y: box.maxY - 24)
        guard let rect = PDFEditing.placed(at: point, size: CGSize(width: 22, height: 22), in: box) else { return }
        editor = AnnotationDraft(page: target, bounds: rect, kind: .text, text: "", quote: selection?.string ?? "", selection: selection?.copy() as? PDFSelection)
        pdfView?.clearSelection()
    }

    func attachNote(to annotation: PDFAnnotation) {
        guard finishEditorIfNeeded(), let document, let page = annotation.page else { return }
        let members = PDFEditing.members(of: annotation, in: document)
        if let note = members.first(where: { $0.1.type == "Text" })?.1 { edit(note); return }
        guard let bounds = PDFEditing.placed(at: CGPoint(x: annotation.bounds.minX, y: annotation.bounds.maxY), size: CGSize(width: 22, height: 22), in: page.bounds(for: .cropBox)) else { return }
        let quote = members.compactMap { $0.0.selection(for: $0.1.bounds)?.string }.joined(separator: "\n")
        editor = AnnotationDraft(page: page, bounds: bounds, kind: .text, text: "", quote: quote, selection: nil, attachedGroup: PDFEditing.group(of: annotation))
    }

    func beginText(on page: PDFPage, at point: CGPoint) {
        guard finishEditorIfNeeded(), page.document === document,
              let rect = PDFEditing.fittedTextRect(text: "", font: PDFEditing.textFont(size: fontSize, bold: false), anchor: point, minWidth: 48, in: page.bounds(for: .cropBox)) else { return }
        editor = AnnotationDraft(page: page, bounds: rect, kind: .freeText, text: "", quote: "", selection: nil)
    }

    func edit(_ annotation: PDFAnnotation) {
        guard finishEditorIfNeeded(), let page = annotation.page, page.document === document,
              annotation.type == "Text" || annotation.type == "FreeText" else { return }
        selectedAnnotation = annotation
        editor = AnnotationDraft(page: page, bounds: annotation.bounds, kind: annotation.type == "Text" ? .text : .freeText,
                                 text: annotation.contents ?? "", quote: annotation.value(forAnnotationKey: PDFEditing.quoteKey) as? String ?? "", selection: nil, original: annotation,
                                 bold: PDFEditing.isBold(annotation.font))
    }

    @discardableResult
    func finishEditorIfNeeded() -> Bool {
        reader.flushViewSettings()
        guard flushWriting() else { return false }
        guard let draft = editor else { return true }
        if pendingEditorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (draft.kind != .text || pendingEditorImages.isEmpty) {
            draft.original?.shouldDisplay = true
            // Emptying an existing text box deletes it (undoable); an empty new box simply disappears.
            if draft.kind == .freeText, let original = draft.original, let document {
                let members = PDFEditing.members(of: original, in: document)
                guard !members.isEmpty else { return false }
                if apply(add: [], remove: members, name: "Delete Text") { editor = nil }
            }
            else { editor = nil }
        } else { saveEditor(draft, text: pendingEditorText, size: pendingEditorSize) }
        return editor == nil
    }

    func saveEditor(_ draft: AnnotationDraft, text: String, size: CGFloat) {
        // A popover may retry with its captured draft after rollback replaced PDFKit objects.
        // Use the live draft's restored target; never append a replacement for a detached original.
        guard let current = editor, current.id == draft.id else { return }
        let draft = current
        guard draft.page.document === document, let document else { editor = nil; return }
        if let original = draft.original, original.page !== draft.page {
            errorMessage = "The annotation changed while editing. Close this editor and select it again."
            return
        }
        let size = size.isFinite ? min(max(size, 8), 96) : 16
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || (draft.kind == .text && !pendingEditorImages.isEmpty) else { return }
        draft.original?.shouldDisplay = true
        if draft.original != nil, body == draft.text,
           (draft.kind != .text || pendingEditorImages == draft.original.map(PDFNotes.images)),
           draft.kind != .freeText || ((draft.original?.font?.pointSize ?? size) == size && draft.ink == nil && draft.bold == PDFEditing.isBold(draft.original?.font)) { editor = nil; return }
        let annotation = draft.original.flatMap(PDFEditing.copy) ?? PDFAnnotation(bounds: draft.bounds, forType: draft.kind, withProperties: nil)
        annotation.contents = body
        annotation.userName = "Folio"
        annotation.shouldPrint = true
        let group = draft.attachedGroup ?? draft.original.flatMap(PDFEditing.group) ?? UUID().uuidString
        annotation.setValue(group, forAnnotationKey: PDFEditing.groupKey)
        annotation.setValue(draft.quote, forAnnotationKey: PDFEditing.quoteKey)
        if draft.kind == .text { annotation.setValue(pendingEditorImages.joined(separator: ","), forAnnotationKey: PDFNotes.imagesKey) }
        var additions: [(PDFPage, PDFAnnotation)] = []
        if draft.kind == .freeText {
            let font = PDFEditing.textFont(size: size, bold: draft.bold)
            annotation.font = font
            annotation.fontColor = draft.ink ?? draft.original?.fontColor ?? textInk
            annotation.color = .clear
            annotation.border = PDFBorder(); annotation.border?.lineWidth = 0
            annotation.bounds = fittedText(body, font: font, bounds: draft.bounds, page: draft.page)
            PDFEditing.recordTextStyle(annotation)
        } else {
            annotation.color = draft.original?.color ?? selectedColor
            if let selection = draft.selection {
                additions = PDFEditing.marks(for: selection, in: document, type: .highlight, color: selectedColor, group: group)
            }
        }
        additions.append((draft.page, annotation))
        let replacement = PDFEditing.replacingHighlights(additions)
        if apply(add: replacement.add, remove: replacement.remove + (draft.original.map { [(draft.page, $0)] } ?? []), name: draft.original == nil ? "Add \(draft.kind == .freeText ? "Text" : "Note")" : "Edit Annotation") {
            editor = nil
            selectedAnnotation = annotation
            tool = .select
        }
    }

    private func fittedText(_ text: String, font: NSFont, bounds: CGRect, page: PDFPage) -> CGRect {
        PDFEditing.fittedTextRect(text: text, font: font, anchor: CGPoint(x: bounds.minX, y: bounds.maxY), minWidth: bounds.width, maxWidth: bounds.width, in: page.bounds(for: .cropBox)) ?? bounds
    }

    func pasteImage(_ image: NSImage, on page: PDFPage, at point: CGPoint) {
        guard page.document === document,
              let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]), png.count <= 20_000_000 else {
            errorMessage = "Choose an image smaller than 20 MB."; return
        }
        let ratio = CGFloat(bitmap.pixelsHigh) / CGFloat(max(1, bitmap.pixelsWide))
        let box = page.bounds(for: .cropBox)
        let width = min(220, box.width, box.height / max(0.01, ratio))
        guard let bounds = PDFEditing.placed(at: point, size: CGSize(width: width, height: width * ratio), in: box),
              let annotation = PDFImageAnnotation(bounds: bounds, png: png) else { return }
        if apply(add: [(page, annotation)], remove: [], name: "Paste Image") {
            selectedAnnotation = annotation; tool = .select
        }
    }

    func deleteNote(_ note: PaperNote) { erase([note.annotation]) }
    func replaceAnnotation(_ old: PDFAnnotation, with new: PDFAnnotation, on page: PDFPage, name: String) -> Bool {
        apply(add: [(page, new)], remove: [(page, old)], name: name)
    }

    @discardableResult
    private func apply(add: [(PDFPage, PDFAnnotation)], remove: [(PDFPage, PDFAnnotation)], name: String) -> Bool {
        prepareAnnotationEdit()
        guard let document, let editHistory, editHistory.document === document else { return false }
        var pages: [PDFPage] = []
        for (page, _) in add + remove where !pages.contains(where: { $0 === page }) { pages.append(page) }
        let changes = pages.map { page in
            var after = page.annotations
            // Replace in place to preserve layering and hit order.
            for (_, old) in remove where old.page === page {
                if let index = after.firstIndex(where: { $0 === old }) {
                    if add.count == remove.count,
                       let pair = remove.firstIndex(where: { $0.1 === old }),
                       add[pair].0 === page {
                        let replacement = add[pair].1
                        after[index] = replacement
                    } else { after.remove(at: index) }
                }
            }
            for (target, annotation) in add where target === page && !after.contains(where: { $0 === annotation }) { after.append(annotation) }
            return PDFEditHistory.Change(page: page, after: after)
        }
        do {
            let changed = try editHistory.commit(name, changes: changes)
            if changed { writingRedo.removeAll(); refreshEdits() }
            return changed
        } catch { editFailed(error); return false }
    }

    private func refreshEdits() {
        saveFailed = false
        if let annotation = selectedAnnotation, annotation.page == nil { selectedAnnotation = nil }
        revision += 1
        pdfView?.setNeedsDisplay(pdfView?.bounds ?? .zero)
    }
    private func editFailed(_ error: Error) {
        cachedNotes = nil
        reader.contentDidChange()
        selectedAnnotation = nil
        // History rollback installs independent snapshots, so the editor's old object is
        // detached. Rebind uniquely to the restored before-state without changing draft ID
        // or pending text/images; a retained popover can then retry safely.
        if var draft = editor, let original = draft.original, original.page == nil {
            let matches = draft.page.annotations.filter {
                $0.type == original.type && $0.bounds == original.bounds && $0.contents == original.contents
                    && PDFEditing.group(of: $0) == PDFEditing.group(of: original)
            }
            if matches.count == 1 {
                draft.original = matches[0]
                if draft.kind == .freeText, inlineText != nil { matches[0].shouldDisplay = false }
                editor = draft
            }
        }
        saveFailed = true
        errorMessage = "Could not save this edit. Your previous PDF was kept. \(error.localizedDescription)"
    }
    /// Vector text rendering temporarily hides PDFKit appearances. Restore only those
    /// tracked flags before copying/snapshotting so history never persists display-only state.
    private func prepareAnnotationEdit() { (pdfView as? ToolPDFView)?.restoreRotatedTexts() }

    func undoAnnotation() {
        guard flushWriting() else { return }
        prepareAnnotationEdit()
        if undoWritingPage() { return }
        do { try editHistory?.undo(); refreshEdits() } catch { editFailed(error) }
    }
    func redoAnnotation() {
        guard flushWriting() else { return }
        prepareAnnotationEdit()
        if redoWritingPage() { return }
        do { try editHistory?.redo(); refreshEdits() } catch { editFailed(error) }
    }
    func undo() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() }
        else { undoAnnotation() }
    }
    func redo() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() }
        else { redoAnnotation() }
    }

    func exportCopy(study: Bool = false) {
        guard finishEditorIfNeeded(), let document, let repository else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (activePaper?.title ?? "Paper") + (study ? " — Study Copy.pdf" : " — Folio.pdf")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard repository.allowsExport(to: destination) else {
            errorMessage = "Choose a destination outside Folio’s managed library."
            return
        }
        do {
            let data = try reader.withOriginalRotation(document, { try StudyCopy.export(document, study: study, imageData: { name in
                guard let id = self.activeID else { return nil }
                return NoteImageStore(root: repository.root).data(name, paper: id)
            }) })
            try data.write(to: destination, options: .atomic)
        } catch { errorMessage = "Export failed. \(error.localizedDescription)" }
    }

    /// Synthetic fixture for the opt-in QA harness; never offered in the product UI.
    func sample() {
        let document = PDFDocument()
        let text = "A guide to reading research\n\nA focused space for your papers and ideas.\n\nAbstract\nResearch begins with a question. Read the abstract, identify the method, and check what evidence supports each claim. Keep your own notes beside the source.\n\n1. Read with a question\nChoose Highlight or Underline, then drag across this sentence. Add a note to keep a question for later.\n\n2. Keep the evidence close\nUse the outline or page controls to navigate. Star a page to return to it. Search the PDF with Command-F.\n\n3. Make it yours\nYour imported papers and annotations stay on this Mac. Export a PDF copy when you are ready to share."
        let bytes = NSMutableData()
        guard let consumer = CGDataConsumer(data: bytes) else { return }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
        let pages = [text,
                     "Follow the evidence\n\nA claim is only as useful as the evidence behind it.\n\nUse this second page to test page navigation, reading-position restoration, and stars.\n\nQuestions to keep nearby\n\nWhat is measured?\nWhich assumptions does the method make?\nWhat would change your interpretation?",
                     "Keep a reading trail\n\nWrite notes in your own words. Mark passages you want to revisit.\n\nYour next session starts from your last saved page. Stars remain in Folio; written comments and highlights travel with an exported PDF copy."]
        for body in pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(box)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            let attributed = NSAttributedString(string: body, attributes: [
                .font: NSFont(name: "Palatino", size: 16) ?? .systemFont(ofSize: 16),
                .foregroundColor: NSColor.black, .paragraphStyle: paragraph
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: box.insetBy(dx: 54, dy: 54), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), path, nil), context)
            context.endPDFPage()
        }
        context.closePDF()
        guard let generated = PDFDocument(data: bytes as Data) else { return }
        for index in 0..<generated.pageCount {
            if let page = generated.page(at: index) { document.insert(page, at: index) }
        }
        let outline = PDFOutline()
        for (index, title) in ["Read with a question", "Follow the evidence", "Keep a reading trail"].enumerated() {
            guard let page = document.page(at: index) else { continue }
            let entry = PDFOutline()
            entry.label = title
            entry.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
            outline.insertChild(entry, at: index)
        }
        document.outlineRoot = outline
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: "A guide to reading research"]
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard document.write(to: temporary) else { errorMessage = "Could not create the sample paper."; return }
        importPDF(temporary)
    }
}

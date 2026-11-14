import AppKit
import Combine
import CoreText
import FolioCore
import PDFKit
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable, Identifiable {
    case all = "All documents", opened = "Opened", notes = "Notes", starred = "Starred pages"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "books.vertical"
        case .opened: "book"
        case .notes: "note.text"
        case .starred: "star"
        }
    }
}

@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var papers: [PaperRecord] = []
    @Published private(set) var document: PDFDocument?
    @Published private(set) var activeID: UUID?
    @Published var reading = false
    @Published var section: LibrarySection = .all
    @Published var page = 1
    @Published var inspector = true
    @Published var showFind = false
    @Published var showNoteEditor = false
    @Published var errorMessage: String?
    @Published var libraryQuery = ""
    @Published private(set) var revision = 0
    weak var pdfView: PDFView?
    let annotationUndo = UndoManager()
    private(set) var repository: LibraryRepository?

    var activePaper: PaperRecord? { papers.first { $0.id == activeID } }
    var notes: [PaperNote] { document.map(PDFNotes.read) ?? [] }
    var isStarred: Bool { activePaper?.starredPages.contains(page) == true }

    init() {
        do {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            // The launch argument isolates disposable UI verification from the real library.
            let arguments = ProcessInfo.processInfo.arguments
            let root: URL
            if let index = arguments.firstIndex(of: "--library-path"), arguments.count > index + 1 {
                root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            } else { root = base.appendingPathComponent("FolioMac", isDirectory: true) }
            let repository = try LibraryRepository(root: root)
            papers = try repository.load()
            self.repository = repository
        } catch {
            // No replacement manifest is written after a failed load.
            errorMessage = "Could not open the local library. \(error.localizedDescription)"
        }
    }

    func choosePDF() {
        guard repository != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Folio keeps a private local copy. Your original stays untouched."
        if panel.runModal() == .OK, let url = panel.url { importPDF(url) }
    }

    func importPDF(_ url: URL) {
        guard let repository else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let record = try repository.importPDF(from: url, existing: papers)
            papers.append(record)
            open(record)
        } catch { errorMessage = error.localizedDescription }
    }

    func open(_ paper: PaperRecord, at target: Int? = nil) {
        guard let repository else { return }
        guard let next = PDFDocument(url: repository.documentURL(for: paper.id)), !next.isLocked, next.pageCount > 0 else {
            errorMessage = "This managed PDF could not be opened. Your library entry was kept."
            return
        }
        annotationUndo.removeAllActions()
        activeID = paper.id
        document = next
        page = min(max(target ?? paper.currentPage, 1), next.pageCount)
        reading = true
        updateActive { $0.lastOpened = Date(); $0.currentPage = page }
    }

    func showLibrary() { reading = false }

    func go(to target: Int) {
        guard let document else { return }
        let index = min(max(target, 1), document.pageCount) - 1
        guard let pdfPage = document.page(at: index) else { return }
        pdfView?.go(to: pdfPage)
        changedPage(index + 1)
    }

    func changedPage(_ number: Int) {
        guard number != page else { return }
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

    private func updateActive(_ edit: (inout PaperRecord) -> Void) {
        guard let id = activeID, let index = papers.firstIndex(where: { $0.id == id }), let repository else { return }
        var next = papers
        edit(&next[index])
        do { try repository.save(next); papers = next }
        catch { errorMessage = "Could not save library metadata. \(error.localizedDescription)" }
    }

    func markSelection(_ type: PDFAnnotationSubtype, color: NSColor) {
        guard let selection = pdfView?.currentSelection, let document else { return }
        var additions: [(PDFPage, PDFAnnotation)] = []
        for line in selection.selectionsByLine() {
            for pdfPage in line.pages {
                let bounds = line.bounds(for: pdfPage)
                guard !bounds.isEmpty, !bounds.isInfinite else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                annotation.color = color
                annotation.userName = "Folio"
                additions.append((pdfPage, annotation))
            }
        }
        guard !additions.isEmpty else { return }
        apply(add: additions, remove: [], document: document, name: type == .highlight ? "Highlight" : "Underline")
        pdfView?.clearSelection()
    }

    func addNote(_ body: String) {
        guard let document, let pdfPage = document.page(at: page - 1) else { return }
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let selected = pdfView?.currentSelection
        let bounds = selected?.pages.contains(pdfPage) == true ? selected!.bounds(for: pdfPage) : .zero
        let box = pdfPage.bounds(for: .cropBox)
        let position = bounds.isEmpty ? CGPoint(x: box.minX + 24, y: box.maxY - 48) : bounds.origin
        let annotation = PDFAnnotation(bounds: CGRect(origin: position, size: CGSize(width: 22, height: 22)),
                                       forType: .text, withProperties: nil)
        annotation.contents = body
        annotation.userName = "Folio"
        annotation.color = .systemYellow
        apply(add: [(pdfPage, annotation)], remove: [], document: document, name: "Add Note")
    }

    func deleteNote(_ note: PaperNote) {
        guard let document, let pdfPage = document.page(at: note.page - 1) else { return }
        apply(add: [], remove: [(pdfPage, note.annotation)], document: document, name: "Delete Note")
    }

    /// PDFKit references never cross actors. The box can be captured by older SDKs'
    /// Sendable undo callback; its contents remain main-actor isolated.
    @MainActor
    private final class AnnotationTransaction {
        let add: [(PDFPage, PDFAnnotation)]
        let remove: [(PDFPage, PDFAnnotation)]
        let document: PDFDocument
        let name: String

        init(add: [(PDFPage, PDFAnnotation)], remove: [(PDFPage, PDFAnnotation)], document: PDFDocument, name: String) {
            self.add = add
            self.remove = remove
            self.document = document
            self.name = name
        }
    }

    private func apply(add: [(PDFPage, PDFAnnotation)], remove: [(PDFPage, PDFAnnotation)],
                       document: PDFDocument, name: String) {
        guard self.document === document, let id = activeID, let repository else { return }
        remove.forEach { $0.0.removeAnnotation($0.1) }
        add.forEach { $0.0.addAnnotation($0.1) }
        do {
            try repository.saveDocument(document, for: id)
            let transaction = AnnotationTransaction(add: add, remove: remove, document: document, name: name)
            annotationUndo.registerUndo(withTarget: self) { owner in
                // Undo is invoked only by this Workspace's main-actor reader buttons.
                // Keep it synchronous so inverse registration stays in the same Undo event.
                MainActor.assumeIsolated {
                    owner.apply(add: transaction.remove, remove: transaction.add,
                                document: transaction.document, name: transaction.name)
                }
            }
            annotationUndo.setActionName(name)
            revision += 1
            pdfView?.setNeedsDisplay(pdfView?.bounds ?? .zero)
        } catch {
            add.forEach { $0.0.removeAnnotation($0.1) }
            remove.forEach { $0.0.addAnnotation($0.1) }
            errorMessage = "Could not save this edit. \(error.localizedDescription)"
        }
    }

    func exportCopy() {
        guard let document, let repository else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (activePaper?.title ?? "Paper") + " — Folio.pdf"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard !destination.standardizedFileURL.path.hasPrefix(repository.root.standardizedFileURL.path + "/") else {
            errorMessage = "Choose a destination outside Folio’s managed library."
            return
        }
        do {
            guard let data = document.dataRepresentation() else { throw LibraryRepository.RepositoryError.encodingFailed }
            try data.write(to: destination, options: .atomic)
        } catch { errorMessage = "Export failed. \(error.localizedDescription)" }
    }

    func sample() {
        let document = PDFDocument()
        let text = "A guide to reading research\n\nA focused space for your papers and ideas.\n\nAbstract\nResearch begins with a question. Read the abstract, identify the method, and check what evidence supports each claim. Keep your own notes beside the source.\n\n1. Read with a question\nSelect this sentence and choose Highlight or Underline in the toolbar. Add a note to keep a question for later.\n\n2. Keep the evidence close\nUse the outline or page controls to navigate. Star a page to return to it. Search the PDF with Command-F.\n\n3. Make it yours\nYour imported papers and annotations stay on this Mac. Export a PDF copy when you are ready to share."
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

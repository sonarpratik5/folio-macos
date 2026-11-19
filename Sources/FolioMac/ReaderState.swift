import SwiftUI
import PDFKit
import FolioCore

enum ReaderFit: String { case width, page, actual, custom }

enum ReaderLayout: String, CaseIterable, Identifiable {
    case singleContinuous, single, twoContinuous, two
    var id: String { rawValue }
    var label: String {
        switch self {
        case .singleContinuous: "Continuous"
        case .single: "Single Page"
        case .twoContinuous: "Two Pages, Continuous"
        case .two: "Two Pages"
        }
    }
    var symbol: String {
        switch self {
        case .singleContinuous: "rectangle.portrait.arrowtriangle.2.down"
        case .single: "rectangle.portrait"
        case .twoContinuous: "rectangle.split.2x1.fill"
        case .two: "rectangle.split.2x1"
        }
    }
    var mode: PDFDisplayMode {
        switch self {
        case .singleContinuous: .singlePageContinuous
        case .single: .singlePage
        case .twoContinuous: .twoUpContinuous
        case .two: .twoUp
        }
    }
    var pagesAcross: CGFloat { self == .twoContinuous || self == .two ? 2 : 1 }
}

/// Pure zoom-sanitising rules, kept separate so restore code can be unit-tested.
enum ReaderZoom {
    static let minimum: CGFloat = 0.25
    static let maximum: CGFloat = 8
    /// A zoom is trusted only when finite and inside the supported range; otherwise callers fall back to Fit Page.
    static func restored(_ value: Double?) -> CGFloat? {
        guard let value, value.isFinite, value >= Double(minimum), value <= Double(maximum) else { return nil }
        return CGFloat(value)
    }
    static func clamped(_ value: CGFloat, lower: CGFloat = minimum, upper: CGFloat = maximum) -> CGFloat {
        guard value.isFinite else { return 1 }
        return min(max(value, max(lower, minimum)), min(upper, maximum))
    }
}

/// Reader view state: in-document search, fit/zoom/rotation/layout and resume position.
@MainActor
final class ReaderState: ObservableObject {
    private weak var workspace: Workspace?
    init(workspace: Workspace) { self.workspace = workspace }

    // MARK: Search
    @Published var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    @Published private(set) var results: [PDFSelection] = []
    @Published private(set) var current = 0
    @Published private(set) var searching = false
    @Published var focusSearchTick = 0
    @Published var focusPageTick = 0
    private var searchTask: Task<Void, Never>?

    private final class SearchPageText {
        let normalized: NormalizedSearchText
        init(_ normalized: NormalizedSearchText) { self.normalized = normalized }
    }
    private let searchTextCache: NSCache<NSNumber, SearchPageText> = {
        let cache = NSCache<NSNumber, SearchPageText>()
        cache.countLimit = 256
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()

    /// Text/annotation changes can replace PDFKit selection backing and original offsets.
    func contentDidChange() {
        searchTextCache.removeAllObjects()
        resetSearch()
        if !normalizedQuery.isEmpty { scheduleSearch() }
    }

    func documentDidChange() {
        flushViewSettings()
        ready = false
        searchTextCache.removeAllObjects()
        clearSearch()
    }

    private func normalizedText(on page: PDFPage, at index: Int) -> NormalizedSearchText {
        let key = NSNumber(value: index)
        if let cached = searchTextCache.object(forKey: key) { return cached.normalized }
        let normalized = NormalizedSearchText(page.string ?? "")
        // Two UTF-16 offset arrays, plus normalized String/NSString storage; estimated cost.
        let cost = max(1, normalized.text.utf16.count * (2 * MemoryLayout<Int>.stride + 4))
        searchTextCache.setObject(SearchPageText(normalized), forKey: key, cost: cost)
        return normalized
    }

    // MARK: View
    @Published private(set) var fit: ReaderFit = .page
    @Published private(set) var layout: ReaderLayout = .singleContinuous
    @Published private(set) var rotation = 0
    @Published private(set) var zoomPercent = 100
    // Page identity survives insertion/removal and writing-page Undo/Redo.
    private var baseRotations: [PDFPage: Int] = [:]
    private var pendingZoom: Double?
    private var lastApplied: CGFloat = 0
    private var lastLayoutSize = CGSize.zero
    /// False until the first real fit after layout; PDFKit's own scale changes before that must not be saved.
    private var ready = false
    private var applying = false
    private var saveTask: Task<Void, Never>?
    private struct PendingView {
        let store: ReadingPositionStore
        let id: UUID
        let position: ReadingPosition
    }
    private var pendingViews: [UUID: PendingView] = [:]
    private var store: ReadingPositionStore?
    private var storeRoot: URL?

    private var view: ToolPDFView? { workspace?.pdfView as? ToolPDFView }

    var matchLabel: String {
        if searching { return "Searching…" }
        if normalizedQuery.isEmpty { return "" }
        return results.isEmpty ? "No results" : "\(current + 1) / \(results.count)"
    }
    private var normalizedQuery: String { NormalizedSearchText(query).text }

    func focusSearch() { focusSearchTick += 1 }
    func focusPage() { focusPageTick += 1 }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = normalizedQuery
        guard !q.isEmpty else { resetSearch(); return }
        searching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        guard let document = workspace?.document else { searching = false; return }
        var found: [PDFSelection] = []
        for index in 0..<document.pageCount {
            if Task.isCancelled { return }
            if let page = document.page(at: index) {
                let normalized = normalizedText(on: page, at: index)
                for (offset, range) in normalized.matches(of: q).enumerated() {
                    if Task.isCancelled { return }
                    if let selection = page.selection(for: range) { found.append(selection) }
                    if offset % 64 == 63 { await Task.yield() }
                }
            }
            await Task.yield()
        }
        guard !Task.isCancelled, workspace?.document === document else { return }
        results = found
        searching = false
        let currentPage = (workspace?.page ?? 1) - 1
        let start = found.firstIndex { selection in
            selection.pages.first.map { document.index(for: $0) >= currentPage } ?? false
        } ?? 0
        show(start)
    }

    private func paint() {
        for (index, selection) in results.enumerated() {
            selection.color = index == current ? NSColor.systemOrange.withAlphaComponent(0.75) : NSColor.systemYellow.withAlphaComponent(0.5)
        }
        view?.highlightedSelections = results.isEmpty ? nil : results
    }

    private func show(_ index: Int) {
        guard !results.isEmpty else { current = 0; paint(); return }
        guard workspace?.finishEditorIfNeeded() != false else { return }
        // Committing an editor can invalidate the search and schedule fresh selections.
        guard !results.isEmpty else { return }
        current = (index + results.count) % results.count
        paint()
        workspace?.rememberPassage()
        view?.go(to: results[current])
    }

    func nextMatch() { show(current + 1) }
    func previousMatch() { show(current - 1) }
    var hasMatches: Bool { !results.isEmpty }

    func clearSearch() { query = ""; resetSearch() }
    func resetSearch() {
        searchTask?.cancel(); searching = false
        results = []; current = 0
        view?.highlightedSelections = nil
    }

    // MARK: Fit / zoom
    func setFit(_ mode: ReaderFit) {
        guard let view else { return }
        fit = mode
        applyFit(view)
        scheduleSave()
    }

    private func setScale(_ scale: CGFloat, in view: PDFView) {
        let clamped = ReaderZoom.clamped(scale, lower: view.minScaleFactor, upper: view.maxScaleFactor)
        applying = true
        defer { applying = false }
        view.autoScales = false
        view.scaleFactor = clamped
        lastApplied = view.scaleFactor
        zoomPercent = Int((view.scaleFactor * 100).rounded())
    }

    func applyFit(_ view: ToolPDFView) {
        guard view.bounds.width > 40, view.bounds.height > 40,
              let page = view.currentPage ?? view.document?.page(at: 0) else { return }
        let box = page.bounds(for: view.displayBox)
        guard box.width > 0, box.height > 0, box.width.isFinite, box.height.isFinite else { return }
        let swapped = page.rotation % 180 != 0
        let w = swapped ? box.height : box.width, h = swapped ? box.width : box.height
        let across = layout.pagesAcross
        switch fit {
        case .width: setScale((view.bounds.width - 32 - (across - 1) * 12) / (across * w), in: view)
        case .page: setScale(min((view.bounds.width - 32 - (across - 1) * 12) / (across * w), (view.bounds.height - 24) / h), in: view)
        case .actual: setScale(1, in: view)
        case .custom:
            if let zoom = ReaderZoom.restored(pendingZoom ?? Double(view.scaleFactor)) { setScale(zoom, in: view) }
            else { fit = .page; pendingZoom = nil; applyFit(view); return }
        }
        pendingZoom = nil
        lastLayoutSize = view.bounds.size
    }

    func zoom(by factor: CGFloat) {
        guard let view else { return }
        fit = .custom
        setScale(view.scaleFactor * factor, in: view)
        scheduleSave()
    }
    func zoomIn() { zoom(by: 1.15) }
    func zoomOut() { zoom(by: 1 / 1.15) }

    /// Called from `ToolPDFView.layout()`: keeps Fit Width / Fit Page in step with window resizes.
    func viewDidLayout(_ view: ToolPDFView) {
        guard fit == .width || fit == .page, view.bounds.size != lastLayoutSize, view.document != nil else { return }
        applyFit(view)
    }

    func scaleChanged(_ view: PDFView) {
        guard ready, !applying, !view.autoScales, view.bounds.width > 40, view.scaleFactor.isFinite,
              abs(view.scaleFactor - lastApplied) > 0.003 else { return }
        lastApplied = view.scaleFactor
        zoomPercent = Int((view.scaleFactor * 100).rounded())
        if fit != .custom { fit = .custom }
        scheduleSave()
    }

    // MARK: Layout / rotation
    func setLayout(_ next: ReaderLayout) {
        guard let view else { return }
        layout = next
        let page = workspace?.page ?? 1
        view.displayMode = next.mode
        view.displayDirection = .vertical
        view.displaysAsBook = false
        if fit == .width || fit == .page { applyFit(view) }
        workspace?.go(to: page)
        scheduleSave()
    }

    func rotate(by delta: Int) {
        guard let view else { return }
        // Keep the current page and the relative position inside it (fraction of the page above the view's top edge).
        let anchor = (view as? ToolPDFView).flatMap { v -> (PDFPage, CGFloat)? in
            guard let page = v.currentPage else { return nil }
            let rect = v.convert(page.bounds(for: v.displayBox), from: page)
            guard rect.height > 1, rect.height.isFinite else { return nil }
            // A page centered inside a roomier view sits below the top edge (negative); anchor that as its top.
            return (page, min(max((v.bounds.minY - rect.minY) / rect.height, 0), 1))
        }
        rotation = ((rotation + delta) % 360 + 360) % 360
        applyRotation(view)
        if fit == .width || fit == .page { applyFit(view) }
        if let (page, fraction) = anchor, let tool = view as? ToolPDFView {
            // Fit/zoom and layout settle over the next passes; re-anchor after each so the final geometry wins.
            let restore: () -> Void = { [weak tool] in
                guard let tool, let scroll = tool.enclosedScrollView(), let document = scroll.documentView,
                      page.document === tool.document else { return }
                tool.layoutSubtreeIfNeeded()
                let rect = tool.convert(page.bounds(for: tool.displayBox), from: page)
                let offset = rect.minY + fraction * rect.height - tool.bounds.minY
                guard offset.isFinite, abs(offset) > 0.5 else { return }
                let clip = scroll.contentView
                var origin = clip.bounds.origin
                origin.y += document.isFlipped == tool.isFlipped ? offset : -offset
                clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: origin, size: clip.bounds.size)).origin)
                scroll.reflectScrolledClipView(clip)
            }
            restore()
            DispatchQueue.main.async { restore() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { restore() }
        }
        scheduleSave()
    }

    private func applyRotation(_ view: PDFView) {
        guard let document = view.document else { return }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let original = baseRotations[page] ?? page.rotation
            baseRotations[page] = original
            page.rotation = (original + rotation) % 360
        }
        view.layoutDocumentView()
        if let tool = view as? ToolPDFView { tool.restoreRotatedTexts(); tool.hideRotatedTexts() }
    }

    func pageStructureDidChange() {
        contentDidChange()
        guard let view else { return }
        applyRotation(view)
        if fit == .width || fit == .page { applyFit(view) }
    }

    /// Rotation is a view-only setting: write PDF bytes with the original page rotations.
    func withOriginalRotation<T>(_ document: PDFDocument, _ body: () throws -> T) rethrows -> T {
        // FreeText hidden from PDFKit while a page is rotated must be visible in the saved bytes.
        let tool = view as? ToolPDFView
        tool?.restoreRotatedTexts()
        defer { if tool?.document === document { tool?.hideRotatedTexts() } }
        guard rotation != 0 else { return try body() }
        let shown = (0..<document.pageCount).compactMap { index -> (PDFPage, Int)? in
            guard let page = document.page(at: index) else { return nil }
            return (page, page.rotation)
        }
        for (page, _) in shown { page.rotation = baseRotations[page] ?? page.rotation }
        defer { for (page, angle) in shown { page.rotation = angle } }
        return try body()
    }

    // MARK: Navigation
    func nextPage() { workspace.map { $0.go(to: $0.page + 1) } }
    func previousPage() { workspace.map { $0.go(to: $0.page - 1) } }
    func firstPage() { workspace?.go(to: 1) }
    func lastPage() { workspace.map { $0.go(to: $0.document?.pageCount ?? 1) } }

    /// Bare-key reader shortcuts from the web app (arrows, J/K, Home/End, G).
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        switch event.keyCode {
        case 124: nextPage(); return true
        case 123: previousPage(); return true
        case 115: firstPage(); return true
        case 119: lastPage(); return true
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "j": nextPage(); return true
        case "k": previousPage(); return true
        case "g": focusPage(); return true
        default: return false
        }
    }

    // MARK: Resume
    private func currentStore() -> ReadingPositionStore? {
        guard let root = workspace?.repository?.root else { return nil }
        if storeRoot != root { store = ReadingPositionStore(root: root); storeRoot = root }
        return store
    }

    func documentDidLoad(_ view: ToolPDFView) {
        documentDidChange()
        baseRotations = [:]
        for index in 0..<(view.document?.pageCount ?? 0) {
            if let page = view.document?.page(at: index) { baseRotations[page] = page.rotation }
        }
        var saved = ReadingPosition()
        if let id = workspace?.activeID, let position = currentStore()?.position(for: id) { saved = position }
        fit = ReaderFit(rawValue: saved.fit) ?? .page
        layout = ReaderLayout(rawValue: saved.layout) ?? .singleContinuous
        rotation = [0, 90, 180, 270].contains(saved.rotation) ? saved.rotation : 0
        pendingZoom = saved.zoom
        if fit == .custom, ReaderZoom.restored(saved.zoom) == nil { fit = .page; pendingZoom = nil }
        ready = false
        view.displayMode = layout.mode
        view.displayDirection = .vertical
        applyRotation(view)
    }

    /// First layout after open: apply the remembered (or default) fit, then return to the saved page.
    func applyInitialFit(_ view: ToolPDFView) {
        applyFit(view)
        if let workspace, let page = view.document?.page(at: workspace.page - 1) { view.go(to: page) }
        // Safety net: never leave an empty canvas. If nothing is visible, drop to Fit Page.
        if view.visiblePages.isEmpty, fit != .page { fit = .page; applyFit(view); view.goToFirstPage(nil) }
        ready = true
    }

    private func scheduleSave() {
        guard ready, let workspace, let id = workspace.activeID, let view,
              view.document === workspace.document,
              ReaderZoom.restored(Double(view.scaleFactor)) != nil, let store = currentStore() else { return }
        // Capture identity and values together, before a different paper can own the view.
        pendingViews[id] = PendingView(store: store, id: id,
            position: ReadingPosition(zoom: Double(view.scaleFactor), fit: fit.rawValue,
                                      layout: layout.rawValue, rotation: rotation))
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.flushViewSettings()
        }
    }

    func flushViewSettings() {
        saveTask?.cancel()
        saveTask = nil
        for (id, pending) in pendingViews {
            do {
                try pending.store.set(pending.position, for: pending.id)
                pendingViews.removeValue(forKey: id)
            } catch {
                workspace?.errorMessage = "Could not save the reading view. Existing settings were kept. \(error.localizedDescription)"
            }
        }
    }
}

/// Reader menus: Edit (find, note), View (zoom, fit, rotate, layout, sidebars), Go (pages) and Annotate (tools, colors).
/// File and Assistant menus live in FolioApp. Every item that needs a paper is disabled without one.
struct ReaderCommands: Commands {
    @ObservedObject var workspace: Workspace

    var body: some Commands {
        let reader = workspace.reader
        let none = workspace.document == nil || !workspace.reading
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find in PDF…") { workspace.showFind = true }.keyboardShortcut("f").disabled(none)
            Button("Find Next") { reader.nextMatch() }.keyboardShortcut("g").disabled(none || !reader.hasMatches)
            Button("Find Previous") { reader.previousMatch() }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(none || !reader.hasMatches)
            Divider()
            Button("Add Note…") { workspace.beginNote(selection: workspace.pdfView?.currentSelection) }
                .keyboardShortcut("n", modifiers: [.command, .shift]).disabled(none)
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { reader.zoomIn() }.keyboardShortcut("=").disabled(none)
            Button("Zoom Out") { reader.zoomOut() }.keyboardShortcut("-").disabled(none)
            Button("Actual Size") { reader.setFit(.actual) }.keyboardShortcut("0").disabled(none)
            Button("Fit Width") { reader.setFit(.width) }.keyboardShortcut("9").disabled(none)
            Button("Fit Page") { reader.setFit(.page) }.keyboardShortcut("8").disabled(none)
            Divider()
            Button("Rotate Left") { reader.rotate(by: -90) }.keyboardShortcut("l").disabled(none)
            Button("Rotate Right") { reader.rotate(by: 90) }.keyboardShortcut("r").disabled(none)
            Menu("Page Layout") {
                ForEach(ReaderLayout.allCases) { item in
                    Toggle(item.label, isOn: Binding(get: { reader.layout == item }, set: { _ in reader.setLayout(item) }))
                }
            }.disabled(none)
            Divider()
            Toggle("Pages Sidebar", isOn: $workspace.showDocumentNavigation).keyboardShortcut("s", modifiers: [.command, .option]).disabled(none)
            Toggle("Notes Sidebar", isOn: $workspace.inspector).keyboardShortcut("i", modifiers: [.command, .option]).disabled(none)
        }
        CommandMenu("Go") {
            Button("Library") { workspace.showLibrary() }.keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button("Return to Previous Passage", action: workspace.returnToPassage).keyboardShortcut("[", modifiers: [.command]).disabled(none || workspace.passageHistory.isEmpty)
            Button("Next Page") { reader.nextPage() }.keyboardShortcut(.downArrow, modifiers: [.command]).disabled(none)
            Button("Previous Page") { reader.previousPage() }.keyboardShortcut(.upArrow, modifiers: [.command]).disabled(none)
            Button("First Page") { reader.firstPage() }.keyboardShortcut(.upArrow, modifiers: [.command, .option]).disabled(none)
            Button("Last Page") { reader.lastPage() }.keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(none)
            Button("Go to Page…") { reader.focusPage() }.keyboardShortcut("g", modifiers: [.command, .option]).disabled(none)
            Divider()
            Button(workspace.isStarred ? "Unstar Current Page" : "Star Current Page", action: workspace.toggleStar)
                .keyboardShortcut("d").disabled(none)
        }
        CommandMenu("Annotate") {
            ForEach(Array(PDFTool.allCases.enumerated()), id: \.element) { index, tool in
                Toggle(tool.label, isOn: Binding(get: { workspace.tool == tool }, set: { _ in workspace.chooseTool(tool) }))
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option]).disabled(none)
            }
            Divider()
            Menu("Color") {
                ForEach(Array(AnnotationPalette.names.enumerated()), id: \.element) { index, name in
                    Toggle(name.capitalized, isOn: Binding(get: { workspace.markColor == name }, set: { _ in workspace.recolor(name) }))
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .control]).disabled(none)
                }
            }.disabled(none)
            Divider()
            Button("Delete Selected Annotation", action: workspace.deleteSelection).disabled(none || workspace.selectedAnnotation == nil)
        }
    }
}

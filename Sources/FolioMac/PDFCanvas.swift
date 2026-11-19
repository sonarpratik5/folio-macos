import SwiftUI
import PDFKit
import FolioCore

struct PDFCanvas: NSViewRepresentable {
    @ObservedObject var workspace: Workspace
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("dimPDFInDarkMode") private var dimPDF = true

    func makeNSView(context: Context) -> ToolPDFView {
        let view = ToolPDFView()
        view.workspace = workspace
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = false
        view.backgroundColor = NSColor(FolioTheme.canvas)
        workspace.pdfView = view
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ view: ToolPDFView, context: Context) {
        if view.document !== workspace.document {
            let target = workspace.page
            view.cancelGesture()
            context.coordinator.restoring = true
            view.document = workspace.document
            if let page = workspace.document?.page(at: target - 1) { view.go(to: page) }
            context.coordinator.restoring = false
            workspace.pdfView = view
            workspace.reader.documentDidLoad(view)
            view.requestInitialFit()
        }
        // A non-interactive tint changes display only; PDF content, annotations and exports retain their colors.
        view.setDimming(colorScheme == .dark && dimPDF)
        view.refreshOverlay()
        context.coordinator.updateEditor(in: view)
        context.coordinator.updateInsight(in: view)
    }

    static func dismantleNSView(_ view: ToolPDFView, coordinator: Coordinator) { coordinator.detach(); view.stopObserving() }
    func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        let workspace: Workspace
        var restoring = false
        private var popover: NSPopover?
        private var draftID: UUID?
        private(set) var insightPopover: NSPopover?
        private var insightID: UUID?
        private var inline: InlineTextController?
        init(workspace: Workspace) { self.workspace = workspace }
        func attach(_ view: PDFView) {
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)
            NotificationCenter.default.addObserver(self, selector: #selector(scaleChanged), name: .PDFViewScaleChanged, object: view)
        }
        func detach() { NotificationCenter.default.removeObserver(self); popover?.close(); insightPopover?.close(); inline?.end(); inline = nil }
        func updateInsight(in view: PDFView) {
            guard let request = workspace.selectionInsight, workspace.reading, view.window != nil,
                  let page = view.document?.page(at: request.page - 1) else {
                insightPopover?.close(); insightPopover = nil; insightID = nil; return
            }
            guard request.id != insightID else { return }
            // Clear ownership before closing so an old dismissal cannot cancel a new selection.
            insightID = nil
            insightPopover?.close()
            let popup = NSPopover()
            popup.behavior = .transient
            popup.animates = false
            popup.delegate = self
            let host = NSHostingController(rootView: SelectionInsightPopup(workspace: workspace, request: request))
            host.sizingOptions = [.preferredContentSize]
            popup.contentViewController = host
            insightPopover = popup; insightID = request.id
            let rect = view.convert(request.bounds, from: page).intersection(view.bounds)
            popup.show(relativeTo: rect.isEmpty ? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) : rect,
                       of: view, preferredEdge: .minY)
        }
        func popoverDidClose(_ notification: Notification) {
            guard let popup = notification.object as? NSPopover, popup === insightPopover,
                  let id = insightID else { return }
            // Removing the host releases the task immediately, including an in-flight request.
            popup.contentViewController = nil
            insightPopover = nil; insightID = nil
            Task { @MainActor [weak self] in
                guard let self, self.workspace.selectionInsight?.id == id else { return }
                self.workspace.selectionInsight = nil
            }
        }
        func updateEditor(in view: PDFView) {
            guard let draft = workspace.editor else {
                popover?.close(); popover = nil; draftID = nil; inline?.end(); inline = nil; return
            }
            if draft.kind == .freeText {
                // Plain text is typed directly on the page: no popover.
                guard draft.id != draftID else { return }
                popover?.close(); popover = nil; inline?.end()
                draftID = draft.id
                inline = InlineTextController(workspace: workspace, view: view, draft: draft)
                return
            }
            if inline != nil { inline?.end(); inline = nil }
            guard draft.id != draftID else { return }
            popover?.close()
            draftID = draft.id
            let popover = NSPopover()
            workspace.pendingEditorText = draft.text
            workspace.pendingEditorSize = draft.original?.font?.pointSize ?? workspace.fontSize
            popover.behavior = .semitransient
            popover.delegate = self
            popover.contentViewController = NSHostingController(rootView: AnnotationEditor(workspace: workspace, draft: draft))
            self.popover = popover
            view.go(to: draft.page)
            let rect = view.convert(draft.bounds, from: draft.page).intersection(view.bounds)
            popover.show(relativeTo: rect.isEmpty ? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) : rect,
                         of: view, preferredEdge: .maxX)
            popover.contentViewController?.view.window?.makeKey()
        }
        func popoverShouldClose(_ popover: NSPopover) -> Bool {
            guard let draft = workspace.editor, draft.id == draftID else { return true }
            return workspace.finishEditorIfNeeded()
        }
        @objc private func scaleChanged(_ notification: Notification) {
            guard let view = notification.object as? ToolPDFView else { return }
            workspace.reader.scaleChanged(view)
        }
        @objc private func pageChanged(_ notification: Notification) {
            guard !restoring, let view = notification.object as? PDFView,
                  let document = view.document, let page = view.currentPage else { return }
            let number = document.index(for: page) + 1
            Task { @MainActor [weak self, weak document] in
                guard let self, self.workspace.document === document else { return }
                self.workspace.changedPage(number)
            }
        }
    }
}

@MainActor
final class ToolPDFView: PDFView {
    private var dimmingView: NSView?
    func setDimming(_ enabled: Bool) {
        if enabled, dimmingView == nil {
            let overlay = PDFDimmingView(frame: bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.wantsLayer = true
            overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
            addSubview(overlay, positioned: .above, relativeTo: nil)
            dimmingView = overlay
        }
        if let dimmingView {
            dimmingView.isHidden = !enabled
            if enabled { addSubview(dimmingView, positioned: .above, relativeTo: nil) }
        }
    }
    weak var workspace: Workspace?
    private var needsInitialFit = false
    private var erased: [PDFAnnotation] = []
    private var dragAnnotation: PDFAnnotation?
    private var dragStart = CGPoint.zero
    private var dragBounds = CGRect.zero
    private var resizing = false
    private var dragOrigin = CGPoint.zero
    private var moved = false
    private var selectionAnchor: (PDFPage, CGPoint)?
    private var erasePrevious: (PDFPage, CGPoint)?
    var erasePreview: [PDFAnnotation] { erased }
    private var selectionInProgress = false
    private lazy var overlay: AnnotationOverlay = {
        let overlay = AnnotationOverlay(frame: bounds)
        overlay.pdfView = self
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)
        return overlay
    }()
    private lazy var marginMarks: MarginMarksView = {
        let marks = MarginMarksView(frame: bounds)
        marks.pdfView = self
        marks.autoresizingMask = [.width, .height]
        addSubview(marks, positioned: .above, relativeTo: overlay)
        return marks
    }()
    var previewBounds: CGRect? { moved ? dragBounds : nil }
    private var observer: NSObjectProtocol?
    private var marksObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard window != nil else { return }
        if needsInitialFit { needsLayout = true }  // the first fit needs a window and a real size
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewPageChanged, .PDFViewVisiblePagesChanged, .PDFViewDisplayModeChanged, .PDFViewDisplayBoxChanged] {
            marksObservers.append(NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshOverlay() }
            })
        }
        // Only the PDF scroll view's clip view: an app-wide observer also fired for the overlay's own bounds changes and recursed.
        if let clip = enclosedScrollView()?.contentView {
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshOverlay() }
            }
        }
    }
    func cancelGesture() {
        erased = []; erasePrevious = nil; dragAnnotation = nil; moved = false
        selectionInProgress = false; selectionAnchor = nil
        refreshOverlay()
    }
    func requestInitialFit() {
        needsInitialFit = true; needsLayout = true
        DispatchQueue.main.async { [weak self] in if self?.needsInitialFit == true { self?.needsLayout = true } }
    }
    /// PDFKit draws FreeText upright (ignoring the view-only page rotation), which wraps it into the rotated
    /// box one letter per line. While a page is view-rotated those annotations are hidden from PDFKit (tracked in
    /// `rotatedHidden`, restored before any save/export and at 0 degrees) and drawn here in page space so they
    /// rotate with the page text.
    private var rotatedHidden: [PDFAnnotation] = []
    func hideRotatedTexts() {
        guard let document else { return }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where annotation.type == "FreeText" && annotation.shouldDisplay
                && !rotatedHidden.contains(where: { $0 === annotation }) {
                annotation.shouldDisplay = false; rotatedHidden.append(annotation)
            }
        }
        setNeedsDisplay(bounds)
    }
    func restoreRotatedTexts() {
        rotatedHidden.forEach { $0.shouldDisplay = true }
        rotatedHidden = []
    }
    /// FreeText is always drawn here as vector text: PDFKit rasterizes FreeText appearances at low resolution
    /// (blurry at reading zoom) and also draws them upright in rotated views. Hidden annotations are restored
    /// by `ReaderState.withOriginalRotation` before every save/export, so saved PDFs keep standard FreeText.
    override func draw(_ page: PDFPage, to context: CGContext) {
        let editing = workspace?.editor?.original
        let texts = page.annotations.filter { annotation in
            annotation.type == "FreeText" && annotation !== editing && !(annotation.contents ?? "").isEmpty
                && (!annotation.shouldDisplay ? rotatedHidden.contains { $0 === annotation } : true)
        }
        let fresh = texts.filter { $0.shouldDisplay }
        fresh.forEach { $0.shouldDisplay = false; rotatedHidden.append($0) }
        super.draw(page, to: context)
        if !fresh.isEmpty { DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay(self?.bounds ?? .zero) } }
        // The context is in the rotated page frame; map unrotated page space into it.
        let box = page.bounds(for: displayBox)
        let rotate: CGAffineTransform
        switch ((page.rotation % 360) + 360) % 360 {
        case 90: rotate = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: box.width)
        case 180: rotate = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: box.width, ty: box.height)
        case 270: rotate = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: box.height, ty: 0)
        default: rotate = .identity
        }
        drawUnderlines(on: page, to: context, transform: rotate.translatedBy(x: -box.minX, y: -box.minY))
        NSGraphicsContext.saveGraphicsState()
        for annotation in texts {
            let font = annotation.font ?? PDFEditing.textFont(size: 16, bold: false)
            let inset = PDFEditing.textInset
            let top = PDFEditing.textTopInset(for: font)
            let bounds = annotation.bounds
            context.saveGState()
            context.concatenate(rotate)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.translateBy(x: bounds.minX, y: bounds.maxY)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let attributes = PDFEditing.textAttributes(font: font, color: annotation.fontColor ?? .black)
            NSAttributedString(string: annotation.contents ?? "", attributes: attributes).draw(with: CGRect(
                x: inset.width, y: top, width: max(1, bounds.width - 2 * inset.width), height: max(1, bounds.height - top)),
                options: [.usesLineFragmentOrigin])
            context.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    /// PDFKit renders an Underline as a hairline in this view whatever its border says, which vanishes on dark
    /// pages. Overdraw a solid 2px line in the annotation's own color (saved PDFs keep the standard annotation).
    private func drawUnderlines(on page: PDFPage, to context: CGContext, transform: CGAffineTransform) {
        let thickness = 2 / max(scaleFactor, 0.05)
        for annotation in page.annotations where annotation.type == "Underline" && annotation.shouldDisplay {
            let b = annotation.bounds
            guard b.width > 1, b.width.isFinite, b.minY.isFinite else { continue }
            context.saveGState()
            context.concatenate(transform)
            context.setFillColor((annotation.color.usingColorSpace(.sRGB) ?? .systemBlue).withAlphaComponent(1).cgColor)
            context.fill(CGRect(x: b.minX, y: b.minY, width: b.width, height: thickness))
            context.restoreGState()
        }
    }
    override func layout() {
        super.layout()
        marginMarks.needsDisplay = true
        workspace?.inlineText?.reposition()
        if needsInitialFit, window != nil, bounds.height > 100, document != nil {
            needsInitialFit = false
            workspace?.reader.applyInitialFit(self)
        } else if !needsInitialFit { workspace?.reader.viewDidLayout(self) }
    }
    func enclosedScrollView() -> NSScrollView? {
        var stack: [NSView] = subviews
        while let view = stack.popLast() {
            if let scroll = view as? NSScrollView { return scroll }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }
    func stopObserving() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        marksObservers.forEach { NotificationCenter.default.removeObserver($0) }
        marksObservers = []
    }
    func refreshOverlay() { overlay.needsDisplay = true; marginMarks.needsDisplay = true; workspace?.inlineText?.reposition() }
    func fitPage() {
        guard let page = currentPage ?? document?.page(at: 0), bounds.height > 0 else { return }
        let box = page.bounds(for: displayBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { return }
        let rotated = page.rotation % 180 != 0
        autoScales = false
        scaleFactor = min((bounds.width - 32) / (rotated ? box.height : box.width),
                          (bounds.height - 24) / (rotated ? box.width : box.height))
    }
    private func location(_ event: NSEvent) -> (PDFPage, CGPoint)? {
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: false) else { return nil }
        return (page, convert(point, to: page))
    }

    override func mouseDown(with event: NSEvent) {
        workspace?.inlineText?.commit() // a click outside the on-page editor commits it
        guard let workspace, workspace.editor == nil, let (page, point) = location(event) else { super.mouseDown(with: event); return }
        window?.makeFirstResponder(self)
        switch workspace.tool {
        case .text:
            // Existing text boxes are selected/dragged/double-click-edited; elsewhere a click starts a new box.
            if textToolStartsNewBox(on: page, at: point, viewPoint: convert(event.locationInWindow, from: nil)) { workspace.beginText(on: page, at: point); return }
        case .erase:
            erased = []; erasePrevious = nil; collectErase(on: page, at: point); return
        case .note, .highlight, .underline, .select: break
        }
        if workspace.tool == .select || workspace.tool == .text {
            if let selected = workspace.selectedAnnotation, selected.page === page,
               ["FreeText", "Stamp"].contains(selected.type ?? ""),
               handleRect(for: selected).insetBy(dx: -5, dy: -5).contains(convert(event.locationInWindow, from: nil)) {
                startDrag(selected, point: point, resizing: true); return
            }
            if let annotation = PDFEditing.hit(at: point, on: page, tolerance: 2 / max(scaleFactor, 0.1)) {
                clearSelection()
                workspace.select(annotation)
                if event.clickCount > 1 && annotation.type == "FreeText" { workspace.edit(annotation) }
                else if ["Text", "FreeText", "Stamp"].contains(annotation.type ?? "") { startDrag(annotation, point: point, resizing: false) }
                return
            }
            workspace.select(nil)
        }
        clearSelection()
        selectionAnchor = (page, point)
        selectionInProgress = true
        super.mouseDown(with: event)
        // PDFKit versions may track the complete selection gesture inside mouseDown.
        DispatchQueue.main.async { [weak self] in
            if NSEvent.pressedMouseButtons & 1 == 0 { self?.finishSelection() }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let workspace else { super.mouseDragged(with: event); return }
        if workspace.tool == .erase {
            if let (page, point) = location(event) { collectErase(on: page, at: point) }; return
        }
        if let annotation = dragAnnotation, let page = annotation.page {
            let point = convert(convert(event.locationInWindow, from: nil), to: page)
            let dx = point.x - dragStart.x, dy = point.y - dragStart.y
            moved = hypot(dx, dy) * scaleFactor > 3
            let box = page.bounds(for: .cropBox)
            if resizing {
                var width = max(36, annotation.bounds.width + dx)
                var height = max(24, annotation.bounds.height - dy)
                if annotation.type == "Stamp" {
                    let ratio = annotation.bounds.height / max(1, annotation.bounds.width)
                    width = min(width, box.maxX - annotation.bounds.minX, (annotation.bounds.maxY - box.minY) / ratio)
                    height = width * ratio
                }
                dragBounds = PDFEditing.contained(CGRect(x: annotation.bounds.minX, y: annotation.bounds.maxY - height, width: width, height: height), in: box) ?? annotation.bounds
            } else {
                dragBounds = PDFEditing.placed(at: CGPoint(x: dragOrigin.x + dx, y: dragOrigin.y + dy), size: annotation.bounds.size, in: box) ?? annotation.bounds
            }
            refreshOverlay(); return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if workspace?.tool == .erase {
            if let (page, point) = location(event) { collectErase(on: page, at: point) }
            workspace?.erase(erased); erased = []; erasePrevious = nil; refreshOverlay(); return
        }
        if let annotation = dragAnnotation {
            if moved { workspace?.move(annotation, to: dragBounds) }
            else if annotation.type == "Text" { workspace?.edit(annotation) }
            dragAnnotation = nil; moved = false; refreshOverlay(); return
        }
        super.mouseUp(with: event)
        finishSelection()
    }

    private func finishSelection() {
        guard selectionInProgress, let workspace else { return }
        selectionInProgress = false
        switch workspace.tool {
        case .highlight: workspace.markSelection(.highlight)
        case .underline: workspace.markSelection(.underline)
        case .note:
            if let selection = currentSelection, !(selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                workspace.beginNote(selection: selection)
            } else if let (page, point) = selectionAnchor { workspace.beginNote(on: page, at: point) }
        case .select: workspace.explainFinishedSelection()
        default: break
        }
    }
    private func collectErase(on page: PDFPage, at point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite, scaleFactor.isFinite else { return }
        let start = erasePrevious.flatMap { $0.0 === page ? $0.1 : nil } ?? point
        let steps = max(1, Int(ceil(hypot(point.x - start.x, point.y - start.y) * scaleFactor / 3)))
        for step in 0...min(steps, 2000) {
            let fraction = CGFloat(step) / CGFloat(min(steps, 2000))
            let sample = CGPoint(x: start.x + (point.x - start.x) * fraction, y: start.y + (point.y - start.y) * fraction)
            if let hit = PDFEditing.hit(at: sample, on: page, tolerance: 4 / max(scaleFactor, 0.1)), !erased.contains(where: { $0 === hit }) { erased.append(hit) }
        }
        erasePrevious = (page, point)
        refreshOverlay()
    }
    private func startDrag(_ annotation: PDFAnnotation, point: CGPoint, resizing: Bool) {
        dragAnnotation = annotation; dragStart = point; dragBounds = annotation.bounds
        dragOrigin = CGPoint(x: annotation.bounds.minX, y: annotation.bounds.maxY)
        self.resizing = resizing; moved = false
    }
    func handleRect(for annotation: PDFAnnotation) -> CGRect {
        guard let page = annotation.page else { return .zero }
        let point = convert(CGPoint(x: annotation.bounds.maxX, y: annotation.bounds.minY), from: page)
        return CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
    }
    /// Right-click on selected text offers the assistant first; nothing is sent until the reader presses Send.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard workspace != nil, let text = currentSelection?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return menu }
        let explain = NSMenuItem(title: "Explain with Folio AI", action: #selector(explainSelection(_:)), keyEquivalent: "")
        explain.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil); explain.target = self
        let ask = NSMenuItem(title: "Ask Folio AI About Selection…", action: #selector(askAboutSelection(_:)), keyEquivalent: "")
        ask.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: nil); ask.target = self
        menu.insertItem(explain, at: 0); menu.insertItem(ask, at: 1); menu.insertItem(.separator(), at: 2)
        return menu
    }
    @objc private func explainSelection(_ sender: Any?) { workspace?.askAboutSelection(explain: true) }
    @objc private func askAboutSelection(_ sender: Any?) { workspace?.askAboutSelection(explain: false) }

    override func keyDown(with event: NSEvent) {
        guard let workspace else { super.keyDown(with: event); return }
        if event.keyCode == 53, workspace.selectionInsight != nil {
            workspace.selectionInsight = nil; return
        }
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "z" {
                event.modifierFlags.contains(.shift) ? workspace.redoAnnotation() : workspace.undoAnnotation(); return
            }
            super.keyDown(with: event); return
        }
        if workspace.editor == nil, event.charactersIgnoringModifiers?.lowercased() == "i",
           !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) {
            workspace.chooseInsightsMode(); return
        }
        if workspace.editor == nil, workspace.reader.handleKey(event) { return }
        if event.keyCode == 53 { cancelGesture(); workspace.select(nil); workspace.chooseTool(.select); return }
        if event.keyCode == 51 || event.keyCode == 117, workspace.selectedAnnotation != nil { workspace.deleteSelection(); return }
        if event.keyCode == 36, let selected = workspace.selectedAnnotation { workspace.edit(selected); return }
        if !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option),
           let key = event.charactersIgnoringModifiers?.lowercased(),
           let tool = ["v": PDFTool.select, "h": .highlight, "u": .underline, "t": .text, "n": .note, "e": .erase][key] {
            workspace.chooseTool(tool); return
        }
        super.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        if event.modifierFlags.contains(.shift), [123, 124, 125, 126].contains(Int(event.keyCode)) {
            workspace?.explainFinishedSelection()
        }
    }
    @objc func paste(_ sender: Any?) {
        guard let image = NSImage(pasteboard: .general), let workspace, let page = currentPage else { return }
        let visible = convert(bounds, to: page).intersection(page.bounds(for: .cropBox))
        workspace.pasteImage(image, on: page, at: CGPoint(x: visible.midX - 110, y: visible.midY + 80))
    }
}

@MainActor
private final class AnnotationOverlay: NSView {
    weak var pdfView: ToolPDFView?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let view = pdfView else { return }
        if let workspace = view.workspace, workspace.skimEnabled {
            for mark in workspace.skimMarks where workspace.skimFacets.contains(mark.facet) && mark.page.document === view.document {
                guard view.visiblePages.contains(where: { $0 === mark.page }) else { continue }
                mark.facet.color.withAlphaComponent(0.18).setFill()
                for rect in mark.rects {
                    let converted = view.convert(rect, from: mark.page)
                    if converted.intersects(bounds) { NSBezierPath(rect: converted).fill() }
                }
            }
        }
        NSColor.systemRed.withAlphaComponent(0.25).setFill()
        for annotation in view.erasePreview {
            if let page = annotation.page { NSBezierPath(rect: view.convert(annotation.bounds, from: page)).fill() }
        }
        guard view.workspace?.inlineText == nil, let selected = view.workspace?.selectedAnnotation, let page = selected.page else { return }
        let rect = view.convert(view.previewBounds ?? selected.bounds, from: page)
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 2, yRadius: 2)
        path.lineWidth = 1.5; path.stroke()
        if ["FreeText", "Stamp"].contains(selected.type ?? "") {
            NSColor.controlAccentColor.setFill(); NSBezierPath(rect: view.handleRect(for: selected)).fill()
        }
    }
}

@MainActor
private final class PDFDimmingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

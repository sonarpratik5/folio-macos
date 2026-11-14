import AppKit
import PDFKit
import FolioCore

/// The on-page text editor: an NSTextView laid over the annotation's page rect (tracking scroll, zoom and page
/// rotation) so text is typed directly on the page. Geometry comes from `PDFEditing` so what you see while typing
/// is what PDFKit renders after commit. Commit/undo go through the normal `Workspace` edit pipeline.
@MainActor
final class InlineTextController: NSObject, NSTextViewDelegate {
    private weak var workspace: Workspace?
    private weak var pdfView: PDFView?
    private(set) var draftID: UUID
    private let page: PDFPage
    private let container = InlineTextContainer()
    let textView = InlineTextView()
    private let strip = InlineFormatStrip()
    private var size: CGFloat
    private var bold: Bool
    private var ink: NSColor
    private var minWidth: CGFloat
    private(set) var rect: CGRect
    private var ended = false

    init(workspace: Workspace, view: PDFView, draft: AnnotationDraft) {
        self.workspace = workspace; self.pdfView = view; self.draftID = draft.id; self.page = draft.page
        size = min(max(workspace.pendingEditorSize, 8), 96)
        bold = draft.bold
        ink = draft.ink ?? draft.original?.fontColor ?? workspace.textInk
        rect = draft.bounds
        minWidth = draft.original?.bounds.width ?? PDFEditing.minTextWidth
        super.init()
        workspace.inlineText = self
        configure(draft)
    }

    private var font: NSFont { PDFEditing.textFont(size: size, bold: bold) }
    private var box: CGRect { page.bounds(for: .cropBox) }

    // MARK: Setup

    private func configure(_ draft: AnnotationDraft) {
        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityLabel("Text box content")
        textView.onCommit = { [weak self] in self?.commit() }
        textView.onBold = { [weak self] in self?.toggleBold() }
        textView.string = draft.text
        container.addSubview(textView)
        strip.controller = self
        strip.selectedColor = draft.original == nil ? workspace?.markColor : nil
        strip.refresh(size: size, bold: bold)

        if let original = draft.original {
            original.shouldDisplay = false // hide PDFKit's own drawing while the overlay is active
            pdfView?.annotationsChanged(on: page)
        }
        pdfView?.addSubview(container)
        pdfView?.addSubview(strip)
        restyle()
        refit()
        reposition()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.ended, let window = self.pdfView?.window else { return }
            window.makeFirstResponder(self.textView)
            self.textView.setSelectedRange(NSRange(location: (self.textView.string as NSString).length, length: 0))
        }
    }

    // MARK: Layout

    /// Re-fits the box to the text (grows, then wraps; height auto-fits) and syncs the draft.
    func refit() {
        let fitted = PDFEditing.fittedTextRect(text: textView.string, font: font, anchor: CGPoint(x: rect.minX, y: rect.maxY),
                                               minWidth: minWidth, maxWidth: max(minWidth, PDFEditing.maxTextWidth), in: box) ?? rect
        rect = fitted
        let inset = PDFEditing.textInset
        textView.textContainerInset = NSSize(width: inset.width, height: PDFEditing.textTopInset(for: font))
        textView.textContainer?.containerSize = CGSize(width: max(1, fitted.width - 2 * inset.width), height: .greatestFiniteMagnitude)
        if workspace?.editor?.id == draftID, workspace?.editor?.bounds != fitted {
            let id = draftID
            // Never publish from inside a SwiftUI update pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.workspace?.editor?.id == id, self.workspace?.editor?.bounds != self.rect else { return }
                self.workspace?.editor?.bounds = self.rect
            }
        }
        reposition()
    }

    /// Positions the overlay exactly over the page rect for the current scroll, zoom and page rotation.
    private var repositioning = false
    private var lastPlacement: (CGRect, CGFloat, Int)?

    func reposition() {
        // Moving the overlay posts bounds/frame notifications that call back here; never re-enter.
        guard !repositioning, !ended, let view = pdfView, view.document === page.document else { return }
        repositioning = true
        defer { repositioning = false }
        let viewRect = view.convert(rect, from: page)
        guard viewRect.width.isFinite, viewRect.height.isFinite, !viewRect.isEmpty else { return }
        let rotation = ((page.rotation % 360) + 360) % 360
        let quarter = rotation % 180 != 0
        let scale = max(0.01, quarter ? viewRect.width / max(rect.height, 0.01) : viewRect.width / max(rect.width, 0.01))
        let center = CGPoint(x: viewRect.midX, y: viewRect.midY)
        let frameSize = CGSize(width: rect.width * scale, height: rect.height * scale)
        let target = CGRect(x: center.x - frameSize.width / 2, y: center.y - frameSize.height / 2, width: frameSize.width, height: frameSize.height)
        if let last = lastPlacement, last.0 == target, last.1 == scale, last.2 == rotation { return }
        lastPlacement = (target, scale, rotation)
        container.frameCenterRotation = 0
        container.frame = CGRect(x: center.x - frameSize.width / 2, y: center.y - frameSize.height / 2, width: frameSize.width, height: frameSize.height)
        container.setBoundsSize(rect.size)
        container.scale = scale
        textView.frame = container.bounds
        container.frameCenterRotation = rotation == 0 ? 0 : CGFloat(view.isFlipped ? rotation : -rotation)
        container.needsDisplay = true

        strip.layoutSubtreeIfNeeded()
        let stripSize = strip.fittingSize
        let bounds = view.bounds
        let above = view.isFlipped ? viewRect.minY - stripSize.height - 8 : viewRect.maxY + 8
        var y = above
        if y < bounds.minY + 2 || y + stripSize.height > bounds.maxY - 2 {
            y = view.isFlipped ? viewRect.maxY + 8 : viewRect.minY - stripSize.height - 8
        }
        let x = min(max(viewRect.minX, bounds.minX + 6), max(bounds.minX + 6, bounds.maxX - stripSize.width - 6))
        strip.frame = CGRect(origin: CGPoint(x: x, y: min(max(y, bounds.minY + 2), max(bounds.minY + 2, bounds.maxY - stripSize.height - 2))), size: stripSize)
    }

    private func restyle() {
        let attributes = PDFEditing.textAttributes(font: font, color: ink)
        textView.typingAttributes = attributes
        textView.insertionPointColor = ink
        if let storage = textView.textStorage {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    // MARK: Format strip actions

    func stepSize(up: Bool) { setSize(PDFEditing.steppedTextSize(from: size, up: up)) }
    private func setSize(_ value: CGFloat) {
        guard value != size else { return }
        size = value
        workspace?.pendingEditorSize = value
        workspace?.fontSize = value
        restyle(); refit(); strip.refresh(size: size, bold: bold); focusText()
    }
    func toggleBold() {
        bold.toggle()
        workspace?.editor?.bold = bold
        restyle(); refit(); strip.refresh(size: size, bold: bold); focusText()
    }
    func pickColor(_ name: String) {
        guard let workspace else { return }
        workspace.markColor = name
        ink = workspace.textInk
        workspace.editor?.ink = ink
        strip.selectedColor = name
        restyle(); strip.refresh(size: size, bold: bold); focusText()
    }
    private func focusText() { pdfView?.window?.makeFirstResponder(textView) }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        guard let workspace else { return }
        let text = textView.string
        workspace.pendingEditorText = text
        if let draft = workspace.editor, draft.id == draftID { workspace.persistNoteDraft(draft, text: text) }
        refit()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { commit(); return true }
        return false
    }

    // MARK: Commit / teardown

    /// Saves (or, when empty, deletes) through the workspace's undoable pipeline.
    @discardableResult
    func commit() -> Bool {
        guard !ended, let workspace else { return true }
        workspace.pendingEditorText = textView.string
        container.isHidden = true; strip.isHidden = true
        if workspace.finishEditorIfNeeded() {
            pdfView?.window?.makeFirstResponder(pdfView)
            DispatchQueue.main.async { [weak self] in self?.end() }
            return true
        }
        container.isHidden = false; strip.isHidden = false
        return false
    }

    /// Removes the overlay and restores the annotation's own drawing. Idempotent.
    func end() {
        guard !ended else { return }
        ended = true
        if workspace?.inlineText === self { workspace?.inlineText = nil }
        if textView.window?.firstResponder === textView { textView.window?.makeFirstResponder(pdfView) }
        container.removeFromSuperview(); strip.removeFromSuperview()
        textView.delegate = nil
        if let original = workspace?.editor?.id == draftID ? workspace?.editor?.original : nil {
            original.shouldDisplay = true
            pdfView?.annotationsChanged(on: page)
        }
        pdfView?.setNeedsDisplay(pdfView?.bounds ?? .zero)
    }
}

// MARK: - Views

final class InlineTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onBold: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) else { return super.performKeyEquivalent(with: event) }
        if event.keyCode == 36 || event.keyCode == 76 { onCommit?(); return true }
        if event.charactersIgnoringModifiers == "b", !event.modifierFlags.contains(.shift) { onBold?(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

/// Flipped, scale-aware host that draws the subtle dashed editing outline.
final class InlineTextContainer: NSView {
    var scale: CGFloat = 1
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let line = 1 / max(scale, 0.1)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: line / 2, dy: line / 2), xRadius: 2 * line, yRadius: 2 * line)
        path.lineWidth = line
        path.setLineDash([4 * line, 3 * line], count: 2, phase: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
        path.stroke()
    }
}

extension ToolPDFView {
    /// Text-tool hit priority: a selected box's handle, then any existing text box, win over starting a new box.
    func textToolStartsNewBox(on page: PDFPage, at point: CGPoint, viewPoint: CGPoint) -> Bool {
        if let selected = workspace?.selectedAnnotation, selected.page === page, selected.type == "FreeText",
           handleRect(for: selected).insetBy(dx: -5, dy: -5).contains(viewPoint) { return false }
        return PDFEditing.hit(at: point, on: page, tolerance: 2 / max(scaleFactor, 0.1))?.type != "FreeText"
    }
}

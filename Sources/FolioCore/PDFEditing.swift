import AppKit
import PDFKit

public enum PDFTool: String, CaseIterable, Identifiable {
    case select, highlight, underline, text, note, erase
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .select: "Select"
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .text: "Text"
        case .note: "Note"
        case .erase: "Eraser"
        }
    }
    public var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .underline: "underline"
        case .text: "textformat"
        case .note: "note.text"
        case .erase: "eraser"
        }
    }
    public var hint: String {
        switch self {
        case .select: "Select text or click an annotation to edit it"
        case .highlight: "Drag across text to highlight"
        case .underline: "Drag across text to underline"
        case .text: "Click the page to write"
        case .note: "Click the page or select a passage to add a note"
        case .erase: "Drag over annotations to erase; Undo restores the whole stroke"
        }
    }
}

public enum PDFEditing {
    public static let groupKey = PDFAnnotationKey(rawValue: "FolioGroup")
    public static let quoteKey = PDFAnnotationKey(rawValue: "FolioQuote")

    public static func editable(_ annotation: PDFAnnotation) -> Bool {
        ["Highlight", "Underline", "FreeText", "Text"].contains(annotation.type ?? "") || imageData(annotation) != nil
    }

    public static let fontSizeKey = PDFAnnotationKey(rawValue: "FolioFontSize")
    public static let inkKey = PDFAnnotationKey(rawValue: "FolioTextInk")
    public static func prepare(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            for annotation in document.page(at: index)?.annotations ?? [] where annotation.type == "FreeText" {
                restoreTextStyle(annotation)
            }
        }
    }
    private static func restoreTextStyle(_ annotation: PDFAnnotation) {
        guard let size = annotation.value(forAnnotationKey: fontSizeKey) as? Double,
              size.isFinite, (8...96).contains(size) else { return }
        annotation.font = textFont(size: CGFloat(size), bold: (annotation.value(forAnnotationKey: boldKey) as? String) == "1")
        annotation.color = .clear
        let border = PDFBorder(); border.lineWidth = 0; annotation.border = border
        if let ink = annotation.value(forAnnotationKey: inkKey) as? String {
            let values = ink.split(separator: ",").compactMap { Double($0) }
            if values.count == 3, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                annotation.fontColor = NSColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: 1)
            }
        }
    }
    public static func recordTextStyle(_ annotation: PDFAnnotation) {
        if let size = annotation.font?.pointSize { annotation.setValue(Double(size), forAnnotationKey: fontSizeKey) }
        annotation.setValue(isBold(annotation.font) ? "1" : "0", forAnnotationKey: boldKey)
        if let color = annotation.fontColor?.usingColorSpace(.deviceRGB) {
            annotation.setValue("\(color.redComponent),\(color.greenComponent),\(color.blueComponent)", forAnnotationKey: inkKey)
        }
    }
    public static let boldKey = PDFAnnotationKey(rawValue: "FolioTextBold")
    public static func textFont(size: CGFloat, bold: Bool) -> NSFont {
        NSFont(name: bold ? "Helvetica-Bold" : "Helvetica", size: size) ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
    }
    public static func isBold(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.bold) || font.fontName.localizedCaseInsensitiveContains("bold")
    }

    // MARK: Inline text geometry (shared by the on-page editor and the saved FreeText box)
    /// Side/bottom padding between a FreeText box edge and its glyphs (calibrated against PDFKit's FreeText
    /// appearance); the editor uses the same values. `textTopInset(for:)` is the matching top padding.
    public static let textInset = CGSize(width: 2, height: 2)
    /// PDFKit lays FreeText lines out at `size + 1` points per line, with the baseline at about 0.75 * size + 3.75
    /// below the box top. This returns the top padding that puts a TextKit baseline in the same spot.
    public static func textTopInset(for font: NSFont) -> CGFloat {
        let storage = NSTextStorage(string: "H", attributes: textAttributes(font: font, color: .black))
        let manager = NSLayoutManager(); let container = NSTextContainer(size: CGSize(width: 1000, height: 1000))
        manager.addTextContainer(container); storage.addLayoutManager(manager); manager.ensureLayout(for: container)
        let baseline = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY + manager.location(forGlyphAt: 0).y
        return max(0, 0.75 * font.pointSize + 3.75 - baseline)
    }
    public static func textAttributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = font.pointSize + 1; style.maximumLineHeight = font.pointSize + 1
        return [.font: font, .foregroundColor: color, .paragraphStyle: style]
    }
    public static let maxTextWidth: CGFloat = 360
    public static let minTextWidth: CGFloat = 28
    public static let textSizeSteps: [CGFloat] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 96]

    /// Next/previous size on the ladder (clamped).
    public static func steppedTextSize(from size: CGFloat, up: Bool) -> CGFloat {
        let steps = textSizeSteps
        if up { return steps.first(where: { $0 > size + 0.01 }) ?? steps[steps.count - 1] }
        return steps.last(where: { $0 < size - 0.01 }) ?? steps[0]
    }

    /// Lays text out with TextKit (the engine NSTextView uses). `wrapWidth == nil` measures the natural, unwrapped size.
    public static func measureText(_ text: String, font: NSFont, wrapWidth: CGFloat?) -> CGSize {
        let storage = NSTextStorage(string: text, attributes: textAttributes(font: font, color: .black))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, wrapWidth ?? 100_000), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container); storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let extra = manager.extraLineFragmentRect
        let lineHeight = font.pointSize + 1
        return CGSize(width: ceil(used.width), height: max(ceil(max(used.maxY, extra.isEmpty ? 0 : extra.maxY)), ceil(lineHeight)))
    }

    /// The FreeText rect for `text`: grows with the text up to `maxWidth`, then wraps; height auto-fits.
    /// The top-left corner (`anchor`, PDF space) stays put, and the result is kept inside `box`.
    public static func fittedTextRect(text: String, font: NSFont, anchor: CGPoint, minWidth: CGFloat = minTextWidth,
                                      maxWidth: CGFloat = maxTextWidth, in box: CGRect) -> CGRect? {
        guard font.pointSize.isFinite, anchor.x.isFinite, anchor.y.isFinite, !box.isEmpty else { return nil }
        let inset = textInset
        let cap = max(1, min(max(maxWidth, minWidth), box.width))
        let natural = measureText(text, font: font, wrapWidth: nil).width
        let width = min(max(ceil(natural) + 2 * inset.width + 2, min(minWidth, cap)), cap)
        let height = measureText(text, font: font, wrapWidth: width - 2 * inset.width).height + textTopInset(for: font) + inset.height
        return placed(at: anchor, size: CGSize(width: width, height: height), in: box)
    }

    public static let imageKey = PDFAnnotationKey(rawValue: "FolioImagePNG")
    public static func imageData(_ annotation: PDFAnnotation) -> Data? {
        guard annotation.type == "Stamp" else { return nil }
        guard let encoded = annotation.value(forAnnotationKey: imageKey) as? String else { return nil }
        return Data(base64Encoded: encoded)
    }
    public static func copy(_ annotation: PDFAnnotation) -> PDFAnnotation? {
        if let data = imageData(annotation), let image = PDFImageAnnotation(bounds: annotation.bounds, png: data) {
            if let group = group(of: annotation) { image.setValue(group, forAnnotationKey: groupKey) }
            return image
        }
        guard let type = ["Highlight": PDFAnnotationSubtype.highlight, "Underline": .underline, "Text": .text, "FreeText": .freeText][annotation.type ?? ""] else {
            return annotation.copy() as? PDFAnnotation
        }
        // PDFAnnotation.copy() can share its underlying PDF dictionary: replacing a saved
        // copy then serializes a deletion. Build an independent standard annotation.
        let copy = PDFAnnotation(bounds: annotation.bounds, forType: type, withProperties: nil)
        copy.contents = annotation.contents; copy.color = annotation.color
        copy.userName = annotation.userName; copy.modificationDate = annotation.modificationDate
        copy.shouldDisplay = annotation.shouldDisplay; copy.shouldPrint = annotation.shouldPrint
        if type == .freeText {
            copy.font = annotation.font; copy.fontColor = annotation.fontColor
            copy.alignment = annotation.alignment
        }
        if let points = annotation.quadrilateralPoints, !points.isEmpty { copy.quadrilateralPoints = points }
        if type == .text { copy.iconType = annotation.iconType }
        copy.border = annotation.border?.copy() as? PDFBorder
        if type == .underline { styleUnderline(copy) }
        for key in [groupKey, quoteKey, fontSizeKey, inkKey, boldKey, PDFNotes.imagesKey, StudyCopy.writingKey, StudyCopy.embeddedImagesKey] {
            if let value = annotation.value(forAnnotationKey: key) { copy.setValue(value, forAnnotationKey: key) }
        }
        if type == .freeText { restoreTextStyle(copy) }
        return copy
    }

    public static func group(of annotation: PDFAnnotation) -> String? {
        annotation.value(forAnnotationKey: groupKey) as? String
    }

    /// All persisted geometry is finite, positive and inside the unrotated crop box.
    public static func contained(_ rect: CGRect, in box: CGRect) -> CGRect? {
        guard [rect.minX, rect.minY, rect.width, rect.height, box.minX, box.minY, box.width, box.height]
            .allSatisfy(\.isFinite), !rect.isNull, !box.isEmpty else { return nil }
        let clipped = rect.standardized.intersection(box.standardized)
        return clipped.isNull || clipped.width < 0.5 || clipped.height < 0.5 ? nil : clipped
    }

    public static func placed(at point: CGPoint, size: CGSize, in box: CGRect) -> CGRect? {
        guard point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, !box.isEmpty else { return nil }
        let width = min(size.width, box.width), height = min(size.height, box.height)
        return contained(CGRect(x: min(max(point.x, box.minX), box.maxX - width),
                                y: min(max(point.y - height, box.minY), box.maxY - height),
                                width: width, height: height), in: box)
    }

    /// PDFKit draws an Underline with the annotation border's thickness; a clear 2pt stroke (standard /BS entry).
    public static func styleUnderline(_ annotation: PDFAnnotation) {
        let border = annotation.border ?? PDFBorder()
        guard border.lineWidth < 2 else { return }
        border.lineWidth = 2
        annotation.border = border
    }

    public static func marks(for selection: PDFSelection, in document: PDFDocument,
                             type: PDFAnnotationSubtype, color: NSColor, group: String = UUID().uuidString) -> [(PDFPage, PDFAnnotation)] {
        guard type == .highlight || type == .underline, !(selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return selection.selectionsByLine().flatMap { line in
            line.pages.compactMap { page in
                guard page.document === document,
                      let bounds = contained(line.bounds(for: page), in: page.bounds(for: .cropBox)) else { return nil }
                let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                annotation.color = color
                if type == .underline { styleUnderline(annotation) }
                annotation.userName = "Folio"
                annotation.setValue(group, forAnnotationKey: groupKey)
                return (page, annotation)
            }
        }
    }

    /// Replace covered highlight geometry while retaining the uncovered pieces and written comments.
    /// Call only when creating highlights, so unrelated annotation edits keep their layering.
    public static func replacingHighlights(_ additions: [(PDFPage, PDFAnnotation)])
        -> (add: [(PDFPage, PDFAnnotation)], remove: [(PDFPage, PDFAnnotation)]) {
        var add = additions
        var remove: [(PDFPage, PDFAnnotation)] = []
        var visited = Set<ObjectIdentifier>()
        for (page, _) in additions where visited.insert(ObjectIdentifier(page)).inserted {
            let covers = additions.filter { $0.0 === page && $0.1.type == "Highlight" }.map { $0.1.bounds }
            guard !covers.isEmpty else { continue }
            for old in page.annotations where old.type == "Highlight" {
                let points = old.quadrilateralPoints ?? []
                var regions: [CGRect] = []
                if points.count >= 4, points.count.isMultiple(of: 4) {
                    for start in stride(from: 0, to: points.count, by: 4) {
                        let quad = points[start..<start + 4].map(\.pointValue)
                        let xs = quad.map(\.x), ys = quad.map(\.y)
                        regions.append(CGRect(x: old.bounds.minX + xs.min()!, y: old.bounds.minY + ys.min()!,
                                              width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!))
                    }
                } else { regions = [old.bounds] }
                guard regions.contains(where: { region in covers.contains { region.intersects($0) } }) else { continue }
                for cover in covers {
                    regions = regions.flatMap { region -> [CGRect] in
                        let overlap = region.intersection(cover)
                        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return [region] }
                        return [CGRect(x: region.minX, y: region.minY, width: overlap.minX - region.minX, height: region.height),
                                CGRect(x: overlap.maxX, y: region.minY, width: region.maxX - overlap.maxX, height: region.height),
                                CGRect(x: overlap.minX, y: region.minY, width: overlap.width, height: overlap.minY - region.minY),
                                CGRect(x: overlap.minX, y: overlap.maxY, width: overlap.width, height: region.maxY - overlap.maxY)]
                            .filter { $0.width > 0.01 && $0.height > 0.01 }
                    }
                }
                let fragments = regions.compactMap { bounds -> PDFAnnotation? in
                    guard let fragment = copy(old) else { return nil }
                    fragment.removeValue(forAnnotationKey: .quadPoints)
                    fragment.bounds = bounds
                    fragment.contents = nil
                    return fragment
                }
                // A comment must survive even when all its colored geometry is replaced.
                if let body = old.contents, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let first = fragments.first { first.contents = body }
                    else {
                        let note = PDFAnnotation(bounds: old.bounds, forType: .text, withProperties: nil)
                        note.contents = body; note.color = old.color; note.userName = old.userName
                        for key in [groupKey, quoteKey, PDFNotes.imagesKey] {
                            if let value = old.value(forAnnotationKey: key) { note.setValue(value, forAnnotationKey: key) }
                        }
                        add.append((page, note))
                    }
                }
                remove.append((page, old))
                add.append(contentsOf: fragments.map { (page, $0) })
            }
        }
        return (add, remove)
    }

    public static func hit(at point: CGPoint, on page: PDFPage, tolerance: CGFloat = 2) -> PDFAnnotation? {
        page.annotations.reversed().first { editable($0) && ($0.shouldDisplay || $0.type == "FreeText") && $0.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
    }

    public static func members(of annotation: PDFAnnotation, in document: PDFDocument) -> [(PDFPage, PDFAnnotation)] {
        guard let page = annotation.page, page.document === document, editable(annotation) else { return [] }
        guard let group = group(of: annotation) else { return [(page, annotation)] }
        return (0..<document.pageCount).flatMap { index -> [(PDFPage, PDFAnnotation)] in
            guard let page = document.page(at: index) else { return [] }
            return page.annotations.filter { editable($0) && self.group(of: $0) == group }.map { (page, $0) }
        }
    }
}

/// Independent annotation snapshots avoid PDFKit's shared-copy/deleted-dictionary state.
/// A successful save is the only transition that enters history; failed inverses retain their stack.
@MainActor
public final class PDFEditHistory {
    public struct Change {
        public let page: PDFPage
        public let before: [PDFAnnotation]
        public let after: [PDFAnnotation]
        public init(page: PDFPage, after: [PDFAnnotation]) {
            self.page = page; self.before = page.annotations; self.after = after
        }
    }
    private struct PageState { let page: PDFPage; let before: [PDFAnnotation]; let after: [PDFAnnotation] }
    private struct Entry { let name: String; let states: [PageState] }
    public enum EditError: Error { case staleDocument, invalidAnnotations }
    public let document: PDFDocument
    private let save: (PDFDocument) throws -> Void
    private var past: [Entry] = []
    private var future: [Entry] = []
    private var expected: [ObjectIdentifier: [PDFAnnotation]] = [:]
    public var depth: Int { past.count }
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var undoName: String { past.last?.name ?? "" }
    public var redoName: String { future.last?.name ?? "" }
    /// A successful structural edit starts a new history branch too.
    public func discardRedo() { future.removeAll() }
    public init(document: PDFDocument, save: @escaping (PDFDocument) throws -> Void) {
        self.document = document; self.save = save
    }
    private func same(_ a: [PDFAnnotation], _ b: [PDFAnnotation]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0 === $1 }
    }
    private func snapshot(_ annotations: [PDFAnnotation]) -> [PDFAnnotation] {
        // PDFKit generates companion Popups when encoding comments. Rebuild these with
        // their parent rather than retaining stale parent pointers through undo/redo.
        let companions = annotations.compactMap { $0.popup }.map(ObjectIdentifier.init)
        return annotations.filter { !companions.contains(ObjectIdentifier($0)) }.map {
            PDFEditing.editable($0) ? (PDFEditing.copy($0) ?? $0) : $0
        }
    }
    @discardableResult
    public func commit(_ name: String, changes: [Change]) throws -> Bool {
        let changes = changes.filter { !same($0.before, $0.after) }
        guard !changes.isEmpty else { return false }
        guard Set(changes.map { ObjectIdentifier($0.page) }).count == changes.count,
              changes.allSatisfy({ $0.page.document === document && same($0.page.annotations, $0.before) }) else { throw EditError.staleDocument }
        guard changes.allSatisfy({ change in
            Set(change.after.map(ObjectIdentifier.init)).count == change.after.count && change.after.allSatisfy { $0.page == nil || $0.page === change.page }
        }) else { throw EditError.invalidAnnotations }
        let entry = Entry(name: name, states: changes.map { PageState(page: $0.page, before: snapshot($0.before), after: snapshot($0.after)) })
        for change in changes { install(change.after, on: change.page) }
        do { try save(document) }
        catch {
            for state in entry.states { install(snapshot(state.before), on: state.page) }
            recordExpected(entry); throw error
        }
        recordExpected(entry)
        past.append(entry); future.removeAll()
        return true
    }
    public func undo() throws {
        guard let entry = past.last else { return }
        try restore(entry, forward: false)
        past.removeLast(); future.append(entry)
    }
    public func redo() throws {
        guard let entry = future.last else { return }
        try restore(entry, forward: true)
        future.removeLast(); past.append(entry)
    }
    private func recordExpected(_ entry: Entry) {
        for state in entry.states { expected[ObjectIdentifier(state.page)] = state.page.annotations }
    }
    private func restore(_ entry: Entry, forward: Bool) throws {
        guard entry.states.allSatisfy({ $0.page.document === document && same($0.page.annotations, expected[ObjectIdentifier($0.page)] ?? []) }) else { throw EditError.staleDocument }
        let rollback = entry.states.map { ($0.page, snapshot($0.page.annotations)) }
        for state in entry.states { install(snapshot(forward ? state.after : state.before), on: state.page) }
        do { try save(document) }
        catch {
            for (page, annotations) in rollback { install(snapshot(annotations), on: page) }
            recordExpected(entry); throw error
        }
        recordExpected(entry)
    }
    private func install(_ desired: [PDFAnnotation], on page: PDFPage) {
        let prefix = zip(page.annotations, desired).prefix { $0 === $1 }.count
        let tail = Array(page.annotations.dropFirst(prefix))
        // Never remove/recreate unrelated links, widgets or other foreign annotation types.
        let protected = tail.filter { old in !PDFEditing.editable(old) && desired.contains(where: { $0 === old }) }
        for annotation in tail where !protected.contains(where: { $0 === annotation }) { page.removeAnnotation(annotation) }
        for annotation in desired.dropFirst(prefix) where !protected.contains(where: { $0 === annotation }) { page.addAnnotation(annotation) }
    }
}

/// PDFKit saves draw(with:in:) as the standard Stamp appearance stream (WWDC22 10089).
/// PNG bytes let Folio reconstruct that appearance after a later move or resize.
public final class PDFImageAnnotation: PDFAnnotation {
    private let bitmap: CGImage
    public init?(bounds: CGRect, png: Data) {
        guard let image = NSImage(data: png), let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.bitmap = bitmap
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        setValue(png.base64EncodedString(), forAnnotationKey: PDFEditing.imageKey)
        setValue(UUID().uuidString, forAnnotationKey: PDFEditing.groupKey)
        userName = "Folio"; contents = "Pasted image"; shouldPrint = true
    }
    public required init?(coder: NSCoder) { return nil }
    public override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.draw(bitmap, in: bounds)
        context.restoreGState()
    }
}

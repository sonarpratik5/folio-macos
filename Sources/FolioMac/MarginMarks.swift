import AppKit
import PDFKit
import FolioCore

/// View-only Skim guides. Saved annotations never produce edge indicators.
@MainActor
final class MarginMarksView: NSView {
    weak var pdfView: ToolPDFView?

    struct Guide {
        let rect: CGRect
        let labelRect: CGRect
        let facets: [SkimFacet]
        let passages: [SkimMark]
        var label: String { facets.map(\.label).joined(separator: " / ") }
    }
    private var hits: [Guide] = []
    private let font = NSFont.systemFont(ofSize: 10, weight: .semibold)

    override var isFlipped: Bool { pdfView?.isFlipped ?? true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return hits.contains { $0.rect.union($0.labelRect).insetBy(dx: -2, dy: -2).contains(local) } ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hits.first(where: { $0.rect.union($0.labelRect).insetBy(dx: -2, dy: -2).contains(point) }),
              let mark = hit.passages.first, let rect = mark.rects.first,
              let workspace = pdfView?.workspace, workspace.editor == nil else { return }
        workspace.rememberPassage()
        pdfView?.go(to: rect.insetBy(dx: -20, dy: -40), on: mark.page)
        window?.makeFirstResponder(pdfView)
    }

    /// Shared by rendering and regression checks; respects document identity and facet filters.
    func guides(on page: PDFPage) -> [Guide] {
        guard let view = pdfView, let workspace = view.workspace, workspace.skimEnabled,
              page.document === view.document else { return [] }
        let passages = workspace.skimMarks.filter { $0.page === page && workspace.skimFacets.contains($0.facet) }
        let pageRect = view.convert(page.bounds(for: view.displayBox), from: page)
        guard pageRect.width > 20 else { return [] }
        let side = MarginLayout.side(forRotation: page.rotation)
        let marks = passages.enumerated().compactMap { index, passage -> MarginLayout.Mark? in
            let rect = passage.rects.map { view.convert($0, from: page) }.reduce(CGRect.null) { $0.union($1) }
            guard !rect.isNull, rect.intersects(bounds.insetBy(dx: -4, dy: -40)) else { return nil }
            // Reserve room for the explicit role label when nearby passages merge.
            let center = side.spansX ? rect.midX : rect.midY
            let halfSpan: CGFloat = side.spansX ? 28 : 23
            return .init(id: index, minY: min(side.spansX ? rect.minX : rect.minY, center - halfSpan),
                         maxY: max(side.spansX ? rect.maxX : rect.maxY, center + halfSpan), color: 0)
        }
        return MarginLayout.markers(for: marks).map { marker in
            let grouped = marker.ids.map { passages[$0] }
            let facets = SkimFacet.allCases.filter { facet in grouped.contains { $0.facet == facet } }
            let title = facets.map(\.label).joined(separator: "\n")
            let width = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 10
            let height = CGFloat(facets.count) * 12 + 6
            // Keep the guide inside the page margin even when fit-to-width leaves no gutter.
            let bar = MarginLayout.rect(for: marker, side: side, pageRect: pageRect, outside: false, flipped: isFlipped)
            let label: CGRect
            switch side {
            case .left: label = CGRect(x: bar.maxX + 3, y: bar.midY - height / 2, width: width, height: height)
            case .right: label = CGRect(x: bar.minX - width - 3, y: bar.midY - height / 2, width: width, height: height)
            case .top, .bottom:
                let inward: CGFloat = (side == .top) == isFlipped ? 1 : -1
                label = CGRect(x: bar.midX - width / 2, y: inward > 0 ? bar.maxY + 3 : bar.minY - height - 3, width: width, height: height)
            }
            return Guide(rect: bar, labelRect: label, facets: facets, passages: grouped)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        hits = []
        guard let view = pdfView, let document = view.document else { return }
        for page in view.visiblePages where page.document === document {
            for guide in guides(on: page) {
                let side = MarginLayout.side(forRotation: page.rotation)
                let count = CGFloat(guide.facets.count)
                for (index, facet) in guide.facets.enumerated() {
                    let stripe = side.spansX
                        ? CGRect(x: guide.rect.minX + CGFloat(index) * guide.rect.width / count, y: guide.rect.minY,
                                 width: guide.rect.width / count, height: guide.rect.height)
                        : CGRect(x: guide.rect.minX, y: guide.rect.minY + CGFloat(index) * guide.rect.height / count,
                                 width: guide.rect.width, height: guide.rect.height / count)
                    facet.color.setFill()
                    NSBezierPath(roundedRect: stripe, xRadius: 2, yRadius: 2).fill()
                }
                NSColor.textBackgroundColor.setFill()
                let capsule = NSBezierPath(roundedRect: guide.labelRect, xRadius: 4, yRadius: 4)
                capsule.fill()
                NSColor.separatorColor.setStroke(); capsule.lineWidth = 0.5; capsule.stroke()
                // NSAttributedString handles both flipped and unflipped PDFView coordinates.
                let text = NSAttributedString(string: guide.facets.map(\.label).joined(separator: "\n"), attributes: [.font: font, .foregroundColor: NSColor.labelColor])
                text.draw(in: guide.labelRect.insetBy(dx: 5, dy: 2))
                hits.append(guide)
            }
        }
    }
}

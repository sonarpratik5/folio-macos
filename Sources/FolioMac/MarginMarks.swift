import AppKit
import PDFKit
import FolioCore

/// Transient margin markers drawn above the PDF view. Never written into the document or exports.
/// Only the marker rectangles accept clicks; page text keeps all other events.
@MainActor
final class MarginMarksView: NSView {
    weak var pdfView: ToolPDFView?
    private struct Hit { var rect: CGRect; var annotations: [PDFAnnotation] }
    private var hits: [Hit] = []
    private var cycle: [ObjectIdentifier: Int] = [:]

    override var isFlipped: Bool { pdfView?.isFlipped ?? true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return hits.contains { $0.rect.insetBy(dx: -3, dy: -2).contains(local) } ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hits.first(where: { $0.rect.insetBy(dx: -3, dy: -2).contains(point) }),
              let workspace = pdfView?.workspace, workspace.editor == nil else { return }
        let key = ObjectIdentifier(hit.annotations[0])
        let index = (cycle[key] ?? -1) + 1
        cycle[key] = index % hit.annotations.count
        let annotation = hit.annotations[index % hit.annotations.count]
        if let page = annotation.page { pdfView?.go(to: annotation.bounds.insetBy(dx: -20, dy: -40), on: page) }
        window?.makeFirstResponder(pdfView)
        if annotation.type == "Text" { workspace.edit(annotation) } else { workspace.select(annotation) }
    }

    override func draw(_ dirtyRect: NSRect) {
        hits = []
        guard let view = pdfView, let document = view.document else { return }
        for page in view.visiblePages where page.document === document {
            let pageRect = view.convert(page.bounds(for: view.displayBox), from: page)
            guard pageRect.width > 20 else { continue }
            var annotations: [PDFAnnotation] = []
            var marks: [MarginLayout.Mark] = []
            var palette: [NSColor] = []
            let side = MarginLayout.side(forRotation: page.rotation)
            for annotation in page.annotations {
                guard let type = annotation.type, ["Highlight", "Underline", "Text"].contains(type) else { continue }
                let rect = view.convert(annotation.bounds, from: page)
                guard rect.minY.isFinite, rect.maxY.isFinite, rect.intersects(bounds.insetBy(dx: -4, dy: -40)) else { continue }
                let color = annotation.color.usingColorSpace(.sRGB) ?? .systemYellow
                let index = palette.firstIndex { abs($0.redComponent - color.redComponent) + abs($0.greenComponent - color.greenComponent) + abs($0.blueComponent - color.blueComponent) < 0.05 } ?? { palette.append(color); return palette.count - 1 }()
                let note = type == "Text" || !(annotation.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                // The span is the mark's extent along the stacking axis: a line's thickness, never its length.
                marks.append(.init(id: annotations.count, minY: side.spansX ? rect.minX : rect.minY, maxY: side.spansX ? rect.maxX : rect.maxY, color: index, isNote: note))
                annotations.append(annotation)
            }
            let room: CGFloat
            switch side {
            case .left: room = pageRect.minX
            case .right: room = bounds.maxX - pageRect.maxX
            case .top: room = isFlipped ? pageRect.minY : bounds.maxY - pageRect.maxY
            case .bottom: room = isFlipped ? bounds.maxY - pageRect.maxY : pageRect.minY
            }
            let outside = room >= 14
            for marker in MarginLayout.markers(for: marks) {
                let rect = MarginLayout.rect(for: marker, side: side, pageRect: pageRect, outside: outside, flipped: isFlipped)
                draw(marker: marker, in: rect, side: side, palette: palette)
                hits.append(Hit(rect: rect, annotations: marker.ids.map { annotations[$0] }))
            }
        }
    }

    private func draw(marker: MarginLayout.Marker, in rect: CGRect, side: MarginLayout.Side, palette: [NSColor]) {
        let colors = marker.colors.compactMap { palette.indices.contains($0) ? palette[$0] : nil }
        let clip = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        let count = CGFloat(max(1, colors.count))
        for (i, color) in colors.enumerated() {
            color.withAlphaComponent(0.9).setFill()
            if side.spansX {
                CGRect(x: rect.minX + CGFloat(i) * rect.width / count, y: rect.minY, width: rect.width / count, height: rect.height).fill()
            } else {
                CGRect(x: rect.minX, y: rect.minY + CGFloat(i) * rect.height / count, width: rect.width, height: rect.height / count).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.18).setStroke()
        clip.lineWidth = 0.5; clip.stroke()
        if marker.hasNote, let glyph = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Note") {
            let size: CGFloat = 11
            let g: CGRect
            switch side {
            case .left: g = CGRect(x: rect.midX - size / 2 - 7, y: rect.minY - 1, width: size, height: size)
            case .right: g = CGRect(x: rect.midX - size / 2 + 7, y: rect.minY - 1, width: size, height: size)
            case .top, .bottom: g = CGRect(x: rect.minX - 1, y: rect.midY - size / 2 + ((side == .top) == isFlipped ? -7 : 7), width: size, height: size)
            }
            glyph.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))?
                .tinted(colors.first ?? .secondaryLabelColor).draw(in: g)
        }
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let image = copy() as! NSImage
        image.lockFocus()
        color.withAlphaComponent(1).set()
        CGRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

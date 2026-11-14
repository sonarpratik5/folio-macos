import XCTest
import AppKit
import CoreText
import PDFKit
@testable import FolioCore

final class PDFEditingTests: XCTestCase {
    private func fixture() throws -> PDFDocument {
        let bytes = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<2 {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            for (index, text) in ["First line of evidence", "Second line of evidence"].enumerated() {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]))
                context.textPosition = CGPoint(x: 45, y: 300 - index * 24)
                CTLineDraw(line, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return try XCTUnwrap(PDFDocument(data: bytes as Data))
    }
    private func mark(_ text: String) -> PDFAnnotation {
        let a = PDFAnnotation(bounds: CGRect(x: 50, y: 100, width: 80, height: 14), forType: .highlight, withProperties: nil)
        a.contents = text; return a
    }

    @MainActor
    func testBoundedEditingSequencesAgainstIndependentHistoryModel() async throws {
        // Every 4-step sequence over 7 operations: 2,401 sequences, 9,604 transitions.
        // Independent model uses arrays of strings and its own history snapshots.
        enum Action: Int, CaseIterable { case add, replace, erase, undo, redo, fail, noop }
        for number in 0..<2401 {
            let document = PDFDocument(); let page = PDFPage(); document.insert(page, at: 0)
            var fail = false
            let history = PDFEditHistory(document: document) { _ in if fail { throw CocoaError(.fileWriteNoPermission) } }
            var state: [String] = [], past: [[String]] = [], future: [[String]] = []
            var digits = number
            for step in 0..<4 {
                let action = Action(rawValue: digits % 7)!; digits /= 7
                var next = state
                switch action {
                case .add: next.append("\(step)")
                case .replace: if !next.isEmpty { next[next.count - 1] = "edit\(step)" }
                case .erase: if !next.isEmpty { next.removeLast() }
                case .undo:
                    try history.undo()
                    if let previous = past.popLast() { future.append(state); state = previous }
                case .redo:
                    try history.redo()
                    if let later = future.popLast() { past.append(state); state = later }
                case .fail:
                    fail = true
                    XCTAssertThrowsError(try history.commit("Failed", changes: [.init(page: page, after: page.annotations + [mark("failed")])]))
                    fail = false
                case .noop:
                    XCTAssertFalse(try history.commit("No-op", changes: [.init(page: page, after: page.annotations)]))
                }
                if [.add, .replace, .erase].contains(action), next != state {
                    // Keep unchanged object identities, just like real replace/delete operations.
                    let after = next.map { text in page.annotations.first(where: { $0.contents == text }) ?? mark(text) }
                    XCTAssertTrue(try history.commit("Edit", changes: [.init(page: page, after: after)]))
                    past.append(state); future = []; state = next
                }
                XCTAssertEqual(page.annotations.map { $0.contents ?? "" }, state, "sequence \(number), step \(step)")
                XCTAssertEqual(history.canUndo, !past.isEmpty)
                XCTAssertEqual(history.canRedo, !future.isEmpty)
            }
        }
    }

    @MainActor
    func testFailureDuringUndoAndRedoPreservesOrderAndHistory() async throws {
        let document = try fixture(), page = try XCTUnwrap(document.page(at: 0))
        let a = mark("back"), b = mark("front")
        page.addAnnotation(a)
        var fail = false
        let history = PDFEditHistory(document: document) { _ in if fail { throw CocoaError(.fileWriteNoPermission) } }
        try history.commit("Add", changes: [.init(page: page, after: [a, b])])
        fail = true
        XCTAssertThrowsError(try history.undo())
        XCTAssertEqual(page.annotations[0].contents, a.contents); XCTAssertEqual(page.annotations[1].contents, b.contents)
        XCTAssertTrue(history.canUndo); XCTAssertFalse(history.canRedo)
        fail = false; try history.undo()
        fail = true; XCTAssertThrowsError(try history.redo())
        XCTAssertEqual(page.annotations.count, 1); XCTAssertEqual(page.annotations[0].contents, a.contents)
        XCTAssertFalse(history.canUndo); XCTAssertTrue(history.canRedo)
        fail = false; try history.redo()
        XCTAssertEqual(PDFEditing.hit(at: CGPoint(x: 60, y: 105), on: page)?.contents, b.contents)
    }

    @MainActor
    func testRejectsWrongDocumentDuplicateAndStaleChanges() async throws {
        let doc = try fixture(), other = try fixture(), page = try XCTUnwrap(doc.page(at: 0))
        let history = PDFEditHistory(document: doc) { _ in XCTFail("Invalid change must not save") }
        let a = mark("a")
        XCTAssertThrowsError(try history.commit("Wrong", changes: [.init(page: try XCTUnwrap(other.page(at: 0)), after: [a])]))
        XCTAssertThrowsError(try history.commit("Duplicate", changes: [.init(page: page, after: [a, a])]))
        let stale = PDFEditHistory.Change(page: page, after: [a]); page.addAnnotation(mark("external"))
        XCTAssertThrowsError(try history.commit("Stale", changes: [stale]))
        XCTAssertFalse(history.canUndo)
    }

    func testGeometryAcrossCropRotationAndOffPagePlacement() throws {
        for rotation in [0, 90, 180, 270] {
            for crop in [CGRect(x: 0, y: 0, width: 300, height: 400), CGRect(x: 20, y: 30, width: 260, height: 340)] {
                let document = try fixture(), page = try XCTUnwrap(document.page(at: 0))
                page.setBounds(crop, for: .cropBox); page.rotation = rotation
                let selection = try XCTUnwrap(document.findString("First line", withOptions: []).first)
                let marks = PDFEditing.marks(for: selection, in: document, type: .highlight, color: .yellow)
                XCTAssertFalse(marks.isEmpty)
                for (_, mark) in marks { XCTAssertTrue(crop.contains(mark.bounds)); XCTAssertGreaterThan(mark.bounds.height, 0) }
                for point in [CGPoint(x: -1000, y: -1000), CGPoint(x: 1000, y: 1000)] {
                    let rect = try XCTUnwrap(PDFEditing.placed(at: point, size: CGSize(width: 220, height: 42), in: crop))
                    XCTAssertTrue(crop.contains(rect)); XCTAssertEqual(rect.width, 220)
                }
            }
        }
        XCTAssertNil(PDFEditing.contained(CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), in: CGRect(x: 0, y: 0, width: 300, height: 400)))
        XCTAssertNil(PDFEditing.placed(at: CGPoint(x: CGFloat.infinity, y: 0), size: CGSize(width: 10, height: 10), in: .zero))
    }

    @MainActor
    func testCrossPageGroupAndEditableTextRoundTripPreservesOriginal() async throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let repository = try LibraryRepository(root: scratch.appendingPathComponent("Library"))
        let source = scratch.appendingPathComponent("source.pdf")
        XCTAssertTrue(try fixture().write(to: source))
        let original = try Data(contentsOf: source)
        let paper = try repository.importPDF(from: source, existing: [])
        let document = try XCTUnwrap(PDFDocument(url: repository.documentURL(for: paper.id)))
        let selection = PDFSelection(document: document)
        for match in document.findString("First line", withOptions: []) { selection.add(match) }
        let marks = PDFEditing.marks(for: selection, in: document, type: .underline, color: .systemGreen, group: "passage")
        XCTAssertEqual(Set(marks.map { document.index(for: $0.0) }), [0, 1])
        let history = PDFEditHistory(document: document) { try repository.saveDocument($0, for: paper.id) }
        let note = PDFAnnotation(bounds: CGRect(x: 40, y: 260, width: 22, height: 22), forType: .text, withProperties: nil)
        note.contents = "A written note"; note.setValue("passage", forAnnotationKey: PDFEditing.groupKey)
        note.setValue("First line", forAnnotationKey: PDFEditing.quoteKey)
        let text = PDFAnnotation(bounds: CGRect(x: 50, y: 130, width: 180, height: 80), forType: .freeText, withProperties: nil)
        text.contents = "Editable text\nA second line"; text.font = .systemFont(ofSize: 16); text.fontColor = .blue; text.color = .clear
        try history.commit("Passage", changes: (0..<2).map { index in
            let page = document.page(at: index)!
            return .init(page: page, after: marks.filter { $0.0 === page }.map(\.1) + (index == 0 ? [note, text] : []))
        })
        XCTAssertEqual(PDFEditing.members(of: note, in: document).count, 3)
        let reopened = try XCTUnwrap(PDFDocument(url: repository.documentURL(for: paper.id)))
        XCTAssertEqual(reopened.pageCount, 2)
        XCTAssertEqual(PDFNotes.read(from: reopened).map(\.body), ["A written note"])
        XCTAssertEqual(reopened.page(at: 0)?.annotations.first { $0.type == "FreeText" }?.contents, text.contents)
        XCTAssertEqual(PDFEditing.members(of: try XCTUnwrap(reopened.page(at: 1)?.annotations.first { $0.type == "Underline" }), in: reopened).count, 3)
        for index in 0..<2 {
            XCTAssertEqual(reopened.page(at: index)?.bounds(for: .mediaBox), document.page(at: index)?.bounds(for: .mediaBox))
            XCTAssertEqual(reopened.page(at: index)?.string, document.page(at: index)?.string)
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
        try history.undo(); XCTAssertTrue(PDFNotes.read(from: document).isEmpty)
        try history.redo(); XCTAssertEqual(PDFNotes.read(from: document).count, 1)
    }

    func testFreeTextAppearanceAndFormattingSurviveSerialization() throws {
        let document = try fixture(), page = try XCTUnwrap(document.page(at: 0))
        let text = PDFAnnotation(bounds: CGRect(x: 40, y: 60, width: 220, height: 80), forType: .freeText, withProperties: nil)
        text.contents = "Editable blue text"; text.font = NSFont(name: "Helvetica", size: 24)
        text.fontColor = NSColor.blue; text.color = .clear
        let border = PDFBorder(); border.lineWidth = 0; text.border = border
        PDFEditing.recordTextStyle(text)
        page.addAnnotation(text)
        let before = try blueBounds(on: page)
        let reopened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
        let reopenedPage = try XCTUnwrap(reopened.page(at: 0))
        let after = try blueBounds(on: reopenedPage)
        XCTAssertEqual(after.height, before.height, accuracy: 2)
        XCTAssertEqual(after.width, before.width, accuracy: 3)
        PDFEditing.prepare(reopened)
        let annotation = try XCTUnwrap(reopenedPage.annotations.first { $0.type == "FreeText" })
        XCTAssertEqual(annotation.font?.pointSize, 24)
        XCTAssertEqual(try XCTUnwrap(annotation.fontColor?.usingColorSpace(.deviceRGB)?.blueComponent), 1, accuracy: 0.001)
        let copy = try XCTUnwrap(PDFEditing.copy(annotation))
        XCTAssertEqual(copy.color.alphaComponent, 0, accuracy: 0.001)
        copy.font = NSFont(name: "Helvetica", size: 18); PDFEditing.recordTextStyle(copy)
        reopenedPage.removeAnnotation(annotation); reopenedPage.addAnnotation(copy)
        let again = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(reopened.dataRepresentation())))
        PDFEditing.prepare(again)
        XCTAssertEqual(again.page(at: 0)?.annotations.first { $0.type == "FreeText" }?.font?.pointSize, 18)
        let image = try XCTUnwrap(again.page(at: 0)).thumbnail(of: CGSize(width: 300, height: 400), for: .mediaBox)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        var yellowPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.redComponent > 0.8, c.greenComponent > 0.7, c.blueComponent < 0.5 { yellowPixels += 1 }
            }
        }
        XCTAssertLessThan(yellowPixels, 10, "FreeText move/edit must not acquire a yellow background")
    }
    private func blueBounds(on page: PDFPage) throws -> CGRect {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(page.thumbnail(of: CGSize(width: 300, height: 400), for: .mediaBox).tiffRepresentation)))
        var pixels = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.blueComponent > 0.7, color.redComponent < 0.4, color.greenComponent < 0.4 {
                    pixels = pixels.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        XCTAssertFalse(pixels.isNull, "Saved FreeText must retain its colored appearance")
        return pixels
    }

    func testImageAppearanceSurvivesReopenAndResizing() throws {
        let image = NSImage(size: CGSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.systemRed.setFill(); rect.fill(); return true
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let document = try fixture(), page = try XCTUnwrap(document.page(at: 0))
        let bounds = CGRect(x: 60, y: 60, width: 160, height: 80)
        page.addAnnotation(try XCTUnwrap(PDFImageAnnotation(bounds: bounds, png: png)))
        let reopened = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
        let stamp = try XCTUnwrap(reopened.page(at: 0)?.annotations.first { $0.type == "Stamp" })
        XCTAssertEqual(PDFEditing.imageData(stamp), png)
        XCTAssertEqual(stamp.bounds, bounds)
        try assertRedImage(on: XCTUnwrap(reopened.page(at: 0)))
        let copy = try XCTUnwrap(PDFEditing.copy(stamp)); copy.bounds = CGRect(x: 80, y: 50, width: 120, height: 60)
        reopened.page(at: 0)?.removeAnnotation(stamp); reopened.page(at: 0)?.addAnnotation(copy)
        let again = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(reopened.dataRepresentation())))
        XCTAssertEqual(again.page(at: 0)?.annotations.first { $0.type == "Stamp" }?.bounds, copy.bounds)
        try assertRedImage(on: XCTUnwrap(again.page(at: 0)))
    }
    private func assertRedImage(on page: PDFPage) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(page.thumbnail(of: CGSize(width: 300, height: 400), for: .mediaBox).tiffRepresentation)))
        var redPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.7, color.greenComponent < 0.5, color.blueComponent < 0.5 { redPixels += 1 }
            }
        }
        XCTAssertGreaterThan(redPixels, 1000, "Saved image must render from its appearance stream")
    }
}

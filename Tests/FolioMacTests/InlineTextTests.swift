import XCTest
import PDFKit
import AppKit
import FolioCore
@testable import FolioMac

final class InlineTextTests: XCTestCase {
    @MainActor
    private func withWorkspace(_ body: (Workspace, PDFPage) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        try body(workspace, try XCTUnwrap(workspace.document?.page(at: 0)))
    }
    private func freeTexts(_ page: PDFPage) -> [PDFAnnotation] { page.annotations.filter { $0.type == "FreeText" } }

    // MARK: Fitting logic
    func testFitGrowsThenWrapsAndKeepsTopLeft() {
        let font = PDFEditing.textFont(size: 16, bold: false)
        let box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let anchor = CGPoint(x: 100, y: 500)
        let short = PDFEditing.fittedTextRect(text: "Hi", font: font, anchor: anchor, in: box)!
        let longer = PDFEditing.fittedTextRect(text: "Hi there, a somewhat longer line", font: font, anchor: anchor, in: box)!
        XCTAssertGreaterThan(longer.width, short.width)
        XCTAssertEqual(short.minX, 100); XCTAssertEqual(short.maxY, 500, accuracy: 0.001)
        let wrapped = PDFEditing.fittedTextRect(text: String(repeating: "word ", count: 40), font: font, anchor: anchor, in: box)!
        XCTAssertEqual(wrapped.width, PDFEditing.maxTextWidth, accuracy: 0.001)
        XCTAssertGreaterThan(wrapped.height, short.height * 2)
        XCTAssertEqual(wrapped.maxY, 500, accuracy: 0.001)
        let multiline = PDFEditing.fittedTextRect(text: "a\nb\nc", font: font, anchor: anchor, in: box)!
        XCTAssertGreaterThan(multiline.height, short.height * 2.5)
    }
    func testFitStaysInsideBoxAndHonorsMinWidth() {
        let font = PDFEditing.textFont(size: 20, bold: true)
        let box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let nearEdge = PDFEditing.fittedTextRect(text: String(repeating: "wide ", count: 30), font: font, anchor: CGPoint(x: 190, y: 20), in: box)!
        XCTAssertTrue(box.contains(nearEdge))
        let kept = PDFEditing.fittedTextRect(text: "x", font: font, anchor: CGPoint(x: 10, y: 150), minWidth: 120, in: box)!
        XCTAssertEqual(kept.width, 120, accuracy: 0.001)
    }
    func testSizeLadderAndBoldRoundTrip() {
        XCTAssertEqual(PDFEditing.steppedTextSize(from: 16, up: true), 18)
        XCTAssertEqual(PDFEditing.steppedTextSize(from: 16, up: false), 14)
        XCTAssertEqual(PDFEditing.steppedTextSize(from: 8, up: false), 8)
        XCTAssertEqual(PDFEditing.steppedTextSize(from: 96, up: true), 96)
        XCTAssertEqual(PDFEditing.steppedTextSize(from: 15, up: true), 16)
        XCTAssertTrue(PDFEditing.isBold(PDFEditing.textFont(size: 12, bold: true)))
        XCTAssertFalse(PDFEditing.isBold(PDFEditing.textFont(size: 12, bold: false)))
    }

    // MARK: Commit, empty-delete, edit, undo
    @MainActor
    func testCommitCreatesFreeTextAndUndoRemovesIt() throws {
        try withWorkspace { workspace, page in
            workspace.beginText(on: page, at: CGPoint(x: 80, y: 600))
            let draft = try XCTUnwrap(workspace.editor)
            XCTAssertEqual(draft.kind, .freeText)
            workspace.pendingEditorText = "Typed on the page"
            let fitted = PDFEditing.fittedTextRect(text: "Typed on the page", font: PDFEditing.textFont(size: workspace.pendingEditorSize, bold: false), anchor: CGPoint(x: draft.bounds.minX, y: draft.bounds.maxY), in: page.bounds(for: .cropBox))!
            workspace.editor?.bounds = fitted
            XCTAssertTrue(workspace.finishEditorIfNeeded())
            let saved = try XCTUnwrap(freeTexts(page).first)
            XCTAssertEqual(saved.contents, "Typed on the page")
            XCTAssertEqual(saved.bounds.width, fitted.width, accuracy: 0.5)
            XCTAssertEqual(saved.bounds.maxY, fitted.maxY, accuracy: 0.5)
            XCTAssertTrue(saved.shouldDisplay)
            workspace.undoAnnotation()
            XCTAssertTrue(freeTexts(page).isEmpty)
            workspace.redoAnnotation()
            XCTAssertEqual(freeTexts(page).count, 1)
        }
    }
    @MainActor
    func testEmptyNewBoxIsDiscardedWithoutHistory() throws {
        try withWorkspace { workspace, page in
            workspace.beginText(on: page, at: CGPoint(x: 80, y: 600))
            workspace.pendingEditorText = "  \n "
            XCTAssertTrue(workspace.finishEditorIfNeeded())
            XCTAssertNil(workspace.editor)
            XCTAssertTrue(freeTexts(page).isEmpty)
            XCTAssertFalse(workspace.canUndo)
        }
    }
    @MainActor
    func testEditExistingThenEmptyDeletesAndUndoRestores() throws {
        try withWorkspace { workspace, page in
            workspace.beginText(on: page, at: CGPoint(x: 80, y: 600))
            workspace.pendingEditorText = "Original"
            XCTAssertTrue(workspace.finishEditorIfNeeded())
            let saved = try XCTUnwrap(freeTexts(page).first)
            workspace.edit(saved)
            workspace.pendingEditorText = "Edited"; workspace.pendingEditorSize = 20
            XCTAssertTrue(workspace.finishEditorIfNeeded())
            XCTAssertEqual(freeTexts(page).first?.contents, "Edited")
            XCTAssertEqual(freeTexts(page).first?.font?.pointSize, 20)
            workspace.edit(try XCTUnwrap(freeTexts(page).first))
            workspace.pendingEditorText = ""
            XCTAssertTrue(workspace.finishEditorIfNeeded())
            XCTAssertTrue(freeTexts(page).isEmpty)
            workspace.undoAnnotation()
            XCTAssertEqual(freeTexts(page).first?.contents, "Edited")
            XCTAssertTrue(try XCTUnwrap(freeTexts(page).first).shouldDisplay)
            workspace.undoAnnotation()
            XCTAssertEqual(freeTexts(page).first?.contents, "Original")
            workspace.undoAnnotation()
            XCTAssertTrue(freeTexts(page).isEmpty)
        }
    }
    @MainActor
    func testFormattingBoldAndInkPersist() throws {
        try withWorkspace { workspace, page in
            workspace.beginText(on: page, at: CGPoint(x: 80, y: 600))
            workspace.pendingEditorText = "Strong"
            workspace.editor?.bold = true
            workspace.markColor = "blue"; workspace.editor?.ink = workspace.textInk
            XCTAssertTrue(workspace.finishEditorIfNeeded())
            let saved = try XCTUnwrap(freeTexts(page).first)
            XCTAssertTrue(PDFEditing.isBold(saved.font))
            let copy = try XCTUnwrap(PDFEditing.copy(saved))
            XCTAssertTrue(PDFEditing.isBold(copy.font))
        }
    }

    // MARK: On-page overlay
    @MainActor
    func testOverlayHidesAnnotationTracksTypingAndCommits() throws {
        try withWorkspace { workspace, page in
            workspace.beginText(on: page, at: CGPoint(x: 80, y: 600))
            workspace.pendingEditorText = "Seed"
            XCTAssertTrue(workspace.finishEditorIfNeeded())
            let saved = try XCTUnwrap(freeTexts(page).first)
            let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
            view.document = workspace.document; view.workspace = workspace; workspace.pdfView = view
            workspace.edit(saved)
            let draft = try XCTUnwrap(workspace.editor)
            let controller = InlineTextController(workspace: workspace, view: view, draft: draft)
            XCTAssertFalse(saved.shouldDisplay, "own drawing must be hidden while the overlay is active")
            XCTAssertEqual(controller.textView.string, "Seed")
            let before = controller.rect
            controller.textView.string = String(repeating: "grow ", count: 60)
            controller.textDidChange(Notification(name: NSText.didChangeNotification))
            XCTAssertGreaterThan(controller.rect.height, before.height)
            XCTAssertEqual(controller.rect.maxY, before.maxY, accuracy: 0.01)
            XCTAssertTrue(controller.commit())
            XCTAssertNil(workspace.editor)
            XCTAssertTrue(saved.shouldDisplay)
            XCTAssertTrue(freeTexts(page).first?.contents?.hasPrefix("grow") == true)
            controller.end()
        }
    }
}

final class InlineTextHitPriorityTests: XCTestCase {
    @MainActor
    func testTextToolDoesNotStartNewBoxOnExistingTextOrHandle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root); workspace.sample()
        let page = try XCTUnwrap(workspace.document?.page(at: 0))
        workspace.beginText(on: page, at: CGPoint(x: 80, y: 600))
        workspace.pendingEditorText = "Existing box"
        XCTAssertTrue(workspace.finishEditorIfNeeded())
        let box = try XCTUnwrap(page.annotations.first { $0.type == "FreeText" })
        let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
        view.document = workspace.document; view.workspace = workspace
        let inside = CGPoint(x: box.bounds.midX, y: box.bounds.midY)
        XCTAssertFalse(view.textToolStartsNewBox(on: page, at: inside, viewPoint: .zero))
        XCTAssertTrue(view.textToolStartsNewBox(on: page, at: CGPoint(x: 400, y: 200), viewPoint: .zero))
        workspace.select(box)
        let handle = view.handleRect(for: box)
        XCTAssertFalse(view.textToolStartsNewBox(on: page, at: CGPoint(x: box.bounds.maxX + 3, y: box.bounds.minY - 3), viewPoint: CGPoint(x: handle.midX, y: handle.midY)))
    }
}

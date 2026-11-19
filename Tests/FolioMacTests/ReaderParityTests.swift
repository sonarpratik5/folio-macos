import XCTest
import AppKit
import PDFKit
import WebKit
import FolioCore
@testable import FolioMac

final class ReaderParityTests: XCTestCase {
    @MainActor
    private func withWorkspace(_ body: (Workspace, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        try body(workspace, root)
    }

    @MainActor
    func testWritingSavesBeforeNavigationAndSurvivesUndoRedoAndReopen() throws {
        try withWorkspace { workspace, _ in
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            workspace.pendingWriting = (page, "Evidence below the source")
            workspace.go(to: 2)
            XCTAssertNil(workspace.pendingWriting)
            XCTAssertEqual(StudyCopy.writing(on: page)?.contents, "Evidence below the source")
            workspace.undoAnnotation()
            XCTAssertNil(StudyCopy.writing(on: page))
            workspace.redoAnnotation()
            XCTAssertEqual(StudyCopy.writing(on: page)?.contents, "Evidence below the source")
            workspace.open(try XCTUnwrap(workspace.activePaper))
            XCTAssertEqual(StudyCopy.writing(on: try XCTUnwrap(workspace.document?.page(at: 0)))?.contents, "Evidence below the source")
        }
    }

    @MainActor
    func testWritingFailureRetainsPendingTextAndBlocksNavigation() throws {
        try withWorkspace { workspace, root in
            let originalPage = workspace.page
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            let documents = root.appendingPathComponent("Documents")
            let backup = root.appendingPathComponent("Documents-held")
            try FileManager.default.moveItem(at: documents, to: backup)
            try Data("block writes".utf8).write(to: documents)
            workspace.showWriting = true
            workspace.pendingWriting = (page, "Must not be lost")
            workspace.toggleWriting()
            XCTAssertTrue(workspace.showWriting)
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.pendingWriting?.text, "Must not be lost")
            workspace.go(to: 2)
            XCTAssertEqual(workspace.page, originalPage)
            XCTAssertEqual(workspace.pendingWriting?.text, "Must not be lost")
            XCTAssertNil(StudyCopy.writing(on: page))
            try FileManager.default.removeItem(at: documents)
            try FileManager.default.moveItem(at: backup, to: documents)
            XCTAssertTrue(workspace.flushWriting())
            XCTAssertEqual(StudyCopy.writing(on: page)?.contents, "Must not be lost")
        }
    }

    @MainActor
    func testClosingPageNotesFlushesAndEmptyingRemovesWriting() throws {
        try withWorkspace { workspace, _ in
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            workspace.toggleWriting()
            workspace.pendingWriting = (page, "Keep on close")
            workspace.toggleWriting()
            XCTAssertFalse(workspace.showWriting)
            XCTAssertNil(workspace.pendingWriting)
            XCTAssertEqual(StudyCopy.writing(on: page)?.contents, "Keep on close")
            workspace.toggleWriting()
            workspace.pendingWriting = (page, "")
            workspace.toggleWriting()
            XCTAssertNil(StudyCopy.writing(on: page))
            workspace.undoAnnotation()
            XCTAssertEqual(StudyCopy.writing(on: page)?.contents, "Keep on close")
        }
    }

    @MainActor
    func testUndoCommitsPendingWritingBeforeUndoAndRedoRestoresIt() throws {
        try withWorkspace { workspace, _ in
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            workspace.pendingWriting = (page, "Newest input")
            workspace.undoAnnotation()
            XCTAssertNil(workspace.pendingWriting)
            XCTAssertNil(StudyCopy.writing(on: page))
            workspace.redoAnnotation()
            XCTAssertEqual(StudyCopy.writing(on: page)?.contents, "Newest input")
        }
    }

    @MainActor
    func testRecursiveFoldersFilterAndRefreshPreserveManagedEditsAndSourceBytes() throws {
        try withWorkspace { workspace, root in
            let source = root.appendingPathComponent("Import")
            let child = source.appendingPathComponent("Methods")
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            let bytes = try XCTUnwrap(workspace.document?.dataRepresentation())
            let a = source.appendingPathComponent("a.pdf"), b = child.appendingPathComponent("b.PDF")
            try bytes.write(to: a); try bytes.write(to: b)
            try FileManager.default.createSymbolicLink(at: child.appendingPathComponent("loop"), withDestinationURL: source)
            workspace.openFolder(source)
            XCTAssertEqual(workspace.libraryPapers.count, 2)
            XCTAssertTrue(workspace.folders.contains(child.path))
            XCTAssertEqual(workspace.libraryPapers.count, 2)
            workspace.selectFolder(child.path)
            let imported = try XCTUnwrap(workspace.libraryPapers.first)
            workspace.open(imported)
            workspace.pendingWriting = (try XCTUnwrap(workspace.document?.page(at: 0)), "Keep these edits")
            XCTAssertTrue(workspace.flushWriting())
            workspace.openFolder(source)
            XCTAssertEqual(workspace.papers.filter { $0.sourcePath == b.path }.count, 1)
            workspace.open(imported)
            XCTAssertEqual(StudyCopy.writing(on: try XCTUnwrap(workspace.document?.page(at: 0)))?.contents, "Keep these edits")
            XCTAssertEqual(try Data(contentsOf: b), bytes)
        }
    }

    @MainActor
    func testPassageReturnPreservesDestinationPointAndClearsAcrossPapers() throws {
        try withWorkspace { workspace, _ in
            let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 500, height: 600))
            view.document = workspace.document; workspace.pdfView = view
            let first = try XCTUnwrap(workspace.document?.page(at: 0))
            view.go(to: PDFDestination(page: first, at: CGPoint(x: 80, y: 500)))
            workspace.rememberPassage()
            let point = try XCTUnwrap(workspace.passageHistory.last?.point)
            workspace.go(to: 3)
            workspace.returnToPassage()
            XCTAssertEqual(workspace.page, 1)
            XCTAssertEqual(try XCTUnwrap(view.currentDestination).point.x, point.x, accuracy: 2)
            XCTAssertEqual(try XCTUnwrap(view.currentDestination).point.y, point.y, accuracy: 2)
            workspace.open(try XCTUnwrap(workspace.activePaper))
            XCTAssertTrue(workspace.passageHistory.isEmpty)
        }
    }

    func testMathHTMLPreservesLaTeXAndEscapesUntrustedContentAndCode() {
        let source = #"Formula $\frac{x_1}{\sqrt{y}}$ p. 2. `<script>$x$</script>`"# + "\n\n$$\\sum_{i=1}^n i$$\n\n<script>bad()</script>"
        let html = MathAnswerHTML.document(source, pageCount: 3, dark: true)
        XCTAssertTrue(html.contains(#"data-tex='\frac{x_1}{\sqrt{y}}'"#))
        XCTAssertTrue(html.contains("folio-page://2"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>bad()"))
        XCTAssertFalse(html.contains("data-tex='x'"))
        XCTAssertTrue(html.contains("font/woff2;base64,"))
        XCTAssertTrue(html.contains("default-src 'none'"))
    }
}

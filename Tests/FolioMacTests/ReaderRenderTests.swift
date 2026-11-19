import XCTest
import PDFKit
import SwiftUI
import AppKit
import FolioCore
@testable import FolioMac

final class ReaderRenderTests: XCTestCase {
    private final class CountingSearchPage: PDFPage {
        var textReads = 0
        override var string: String? { textReads += 1; return "Synthetic cache probe" }
    }

    @MainActor
    private func waitForSearch(_ reader: ReaderState) async throws {
        let deadline = Date().addingTimeInterval(5)
        while reader.searching, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(reader.searching, "Search did not finish")
    }

    @MainActor
    func testSearchReusesTextAndInvalidatesAfterEditsAndDocumentSwitch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let document = try XCTUnwrap(workspace.document)
        let probe = CountingSearchPage()
        document.insert(probe, at: document.pageCount)
        workspace.revision += 1
        probe.textReads = 0
        let reader = workspace.reader
        reader.query = "research"
        try await waitForSearch(reader)
        XCTAssertTrue(reader.hasMatches)
        XCTAssertEqual(probe.textReads, 1)
        reader.query = "reading"
        try await waitForSearch(reader)
        XCTAssertTrue(reader.hasMatches)
        XCTAssertEqual(probe.textReads, 1, "New queries should reuse extracted page text")
        reader.clearSearch()
        reader.query = "research"
        try await waitForSearch(reader)
        XCTAssertEqual(probe.textReads, 1, "Closing Find should preserve the bounded text cache")

        workspace.revision += 1
        try await waitForSearch(reader)
        XCTAssertEqual(probe.textReads, 2)
        XCTAssertTrue(reader.hasMatches)
        workspace.open(try XCTUnwrap(workspace.activePaper))
        XCTAssertTrue(reader.query.isEmpty)
        XCTAssertTrue(reader.results.isEmpty)
        reader.query = "reading"
        try await waitForSearch(reader)
        XCTAssertTrue(reader.hasMatches)
        XCTAssertTrue(reader.results.allSatisfy { $0.pages.allSatisfy { $0.document === workspace.document } })
    }

    @MainActor
    func testFindNextSafelyCommitsEditorThatInvalidatesSelections() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let reader = workspace.reader
        reader.query = "research"
        try await waitForSearch(reader)
        XCTAssertTrue(reader.hasMatches)
        workspace.beginNote()
        workspace.pendingEditorText = "Persist while navigating Find"
        reader.nextMatch()
        try await waitForSearch(reader)
        XCTAssertNil(workspace.editor)
        XCTAssertEqual(workspace.notes.first?.body, "Persist while navigating Find")
        XCTAssertTrue(reader.hasMatches)
    }

    @MainActor
    func testSearchCancellationAndPageInsertionKeepResultsCurrent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let reader = workspace.reader
        reader.query = "research"
        reader.query = "no such synthetic term"
        try await waitForSearch(reader)
        XCTAssertTrue(reader.results.isEmpty)
        reader.query = "research"
        try await waitForSearch(reader)
        XCTAssertTrue(reader.hasMatches)
        let page = try XCTUnwrap(reader.results.first?.pages.first)
        workspace.insertWritingPage(after: 0)
        try await waitForSearch(reader)
        XCTAssertTrue(reader.hasMatches)
        XCTAssertTrue(reader.results.first?.pages.first === page)
        XCTAssertEqual(workspace.document?.index(for: page), 1)
        reader.clearSearch()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(reader.results.isEmpty)
        XCTAssertFalse(reader.searching)
    }

    @MainActor
    func testNoteUpdateReportsFailedSaveAndCanRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        workspace.beginNote()
        workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Original note", size: 16)
        let managed = try XCTUnwrap(workspace.repository).documentURL(for: try XCTUnwrap(workspace.activeID))
        let preserved = root.appendingPathComponent("preserved.pdf")
        try FileManager.default.moveItem(at: managed, to: preserved)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
        XCTAssertFalse(workspace.updateNote(try XCTUnwrap(workspace.notes.first), body: "Revised note", images: []))
        XCTAssertEqual(workspace.notes.first?.body, "Original note")
        XCTAssertNotNil(workspace.errorMessage)
        try FileManager.default.removeItem(at: managed)
        try FileManager.default.moveItem(at: preserved, to: managed)
        XCTAssertTrue(workspace.updateNote(try XCTUnwrap(workspace.notes.first), body: "Revised note", images: []))
        let saved = try XCTUnwrap(PDFDocument(data: Data(contentsOf: managed)))
        XCTAssertEqual(PDFNotes.read(from: saved).first?.body, "Revised note")
        workspace.undoAnnotation()
        XCTAssertEqual(workspace.notes.first?.body, "Original note")
    }

    @MainActor
    func testWritingPageStartsNewUndoBranch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        workspace.beginNote()
        workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Discarded redo branch", size: 16)
        workspace.undoAnnotation()
        XCTAssertTrue(workspace.canRedo)
        workspace.insertWritingPage(after: 1)
        XCTAssertFalse(workspace.canRedo)
        workspace.redoAnnotation()
        XCTAssertTrue(workspace.notes.isEmpty)
        workspace.undoAnnotation()
        XCTAssertTrue(workspace.canRedo)
        workspace.redoAnnotation()
        XCTAssertTrue(workspace.notes.isEmpty)
        XCTAssertFalse(workspace.canRedo)
    }

    @MainActor
    func testWritingPageInsertUndoRedoKeepsRotationViewOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let document = try XCTUnwrap(workspace.document)
        let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 700))
        view.document = document
        workspace.pdfView = view
        workspace.reader.documentDidLoad(view)
        workspace.reader.rotate(by: 90)
        let originalCount = document.pageCount
        let url = try XCTUnwrap(workspace.repository).documentURL(for: try XCTUnwrap(workspace.activeID))
        func assertRotations(count: Int) throws {
            XCTAssertNil(workspace.errorMessage)
            XCTAssertEqual(document.pageCount, count)
            let saved = try XCTUnwrap(PDFDocument(data: Data(contentsOf: url)))
            XCTAssertEqual(saved.pageCount, count)
            for index in 0..<count {
                XCTAssertEqual(document.page(at: index)?.rotation, 90, "Displayed page \(index)")
                XCTAssertEqual(saved.page(at: index)?.rotation, 0, "Saved page \(index)")
            }
        }
        workspace.insertWritingPage(after: 1)
        try assertRotations(count: originalCount + 1)
        workspace.undoAnnotation()
        try assertRotations(count: originalCount)
        workspace.redoAnnotation()
        try assertRotations(count: originalCount + 1)
        let page = try XCTUnwrap(document.page(at: 0))
        workspace.beginNote(on: page)
        workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Note after page insertion", size: 16)
        try assertRotations(count: originalCount + 1)
        workspace.undoAnnotation()
        workspace.undoAnnotation()
        try assertRotations(count: originalCount)
    }

    func testZoomClampingAndRestore() {
        XCTAssertNil(ReaderZoom.restored(nil))
        XCTAssertNil(ReaderZoom.restored(0))
        XCTAssertNil(ReaderZoom.restored(0.1))
        XCTAssertNil(ReaderZoom.restored(.nan))
        XCTAssertNil(ReaderZoom.restored(.infinity))
        XCTAssertNil(ReaderZoom.restored(100))
        XCTAssertEqual(ReaderZoom.restored(1.5), 1.5)
        XCTAssertEqual(ReaderZoom.clamped(0), ReaderZoom.minimum)
        XCTAssertEqual(ReaderZoom.clamped(.nan), 1)
        XCTAssertEqual(ReaderZoom.clamped(50), ReaderZoom.maximum)
        XCTAssertEqual(ReaderZoom.clamped(2, lower: 0.1, upper: 100), 2)
    }

    func testAnnotationPaletteIsConsistent() {
        XCTAssertEqual(AnnotationPalette.names, ["yellow", "green", "blue", "pink"])
        XCTAssertEqual(AnnotationPalette.normalized("purple"), "yellow")
        let defaults = UserDefaults(suiteName: "folio-palette-\(UUID().uuidString)")!
        XCTAssertEqual(AnnotationPalette.stored(defaults), "yellow")
        AnnotationPalette.store("pink", defaults)
        XCTAssertEqual(AnnotationPalette.stored(defaults), "pink")
    }

    @MainActor
    func testWorkspaceColorMatchesPalette() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        for name in AnnotationPalette.names {
            workspace.markColor = name
            XCTAssertEqual(workspace.selectedColor, AnnotationPalette.fill(name))
        }
        workspace.markColor = "yellow"
    }

    @MainActor
    private func attachReader(_ workspace: Workspace) throws -> ToolPDFView {
        let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.document = try XCTUnwrap(workspace.document)
        view.minScaleFactor = ReaderZoom.minimum; view.maxScaleFactor = ReaderZoom.maximum
        workspace.pdfView = view
        workspace.reader.documentDidLoad(view)
        workspace.reader.applyInitialFit(view)
        return view
    }

    @MainActor
    func testCustomZoomSurvivesRotationLayoutAndRepeatedFit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let view = try attachReader(workspace)
        workspace.reader.zoomIn()
        let scale = view.scaleFactor
        workspace.reader.rotate(by: 90)
        workspace.reader.setLayout(.two)
        workspace.reader.applyFit(view)
        workspace.reader.applyFit(view)
        XCTAssertEqual(workspace.reader.fit, .custom)
        XCTAssertEqual(view.scaleFactor, scale, accuracy: 0.001)
        workspace.reader.flushViewSettings()
        let saved = try XCTUnwrap(ReadingPositionStore(root: root).position(for: XCTUnwrap(workspace.activeID)))
        XCTAssertEqual(saved.fit, "custom")
        XCTAssertEqual(saved.rotation, 90)
        XCTAssertEqual(saved.layout, "two")
    }

    @MainActor
    func testDeferredViewSaveKeepsOriginalPaperIdentityAcrossSwitch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let first = try XCTUnwrap(workspace.activePaper)
        let view = try attachReader(workspace)
        workspace.reader.zoomIn()
        workspace.reader.rotate(by: 90)
        let expectedScale = view.scaleFactor
        // A new sample imports/opens a different managed paper before the debounce expires.
        workspace.sample()
        let second = try XCTUnwrap(workspace.activeID)
        XCTAssertNotEqual(first.id, second)
        view.document = workspace.document
        workspace.reader.documentDidLoad(view)
        workspace.reader.applyInitialFit(view)
        try await Task.sleep(nanoseconds: 650_000_000)
        let saved = ReadingPositionStore(root: root)
        let firstPosition = try XCTUnwrap(saved.position(for: first.id))
        XCTAssertEqual(try XCTUnwrap(firstPosition.zoom), Double(expectedScale), accuracy: 0.001)
        XCTAssertEqual(firstPosition.rotation, 90)
        XCTAssertNil(saved.position(for: second), "An old save must not assign settings to the newly opened paper")
    }

    @MainActor
    func testFailedViewSaveRetriesOriginalSnapshotAfterPaperSwitch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let first = try XCTUnwrap(workspace.activeID)
        let view = try attachReader(workspace)
        workspace.reader.zoomIn()
        let expectedScale = view.scaleFactor
        let file = root.appendingPathComponent("reading-positions.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        workspace.reader.flushViewSettings()
        XCTAssertNotNil(workspace.errorMessage)
        workspace.sample()
        XCTAssertNotEqual(first, workspace.activeID)
        try FileManager.default.removeItem(at: file)
        workspace.reader.flushViewSettings()
        let saved = try XCTUnwrap(ReadingPositionStore(root: root).position(for: first))
        XCTAssertEqual(try XCTUnwrap(saved.zoom), Double(expectedScale), accuracy: 0.001)
        XCTAssertNil(ReadingPositionStore(root: root).position(for: try XCTUnwrap(workspace.activeID)))
    }

    @MainActor
    func testCorruptSavedZoomFallsBackToFitPage() async throws {
        try await assertVisible(corrupt: ReadingPosition(zoom: 0.01, fit: "custom"))
        try await assertVisible(corrupt: ReadingPosition(zoom: 1e9, fit: "custom"))
    }

    @MainActor
    func testReaderShowsPageWithFiniteScale() async throws { try await assertVisible(corrupt: nil) }

    @MainActor
    private func assertVisible(corrupt: ReadingPosition?) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        if let corrupt, let id = workspace.activeID {
            try ReadingPositionStore(root: root).set(corrupt, for: id)
            workspace.showLibrary()
            workspace.open(try XCTUnwrap(workspace.activePaper))
        }
        let host = NSHostingView(rootView: ReaderView(workspace: workspace).frame(width: 1000, height: 800))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        if ProcessInfo.processInfo.environment["FOLIO_RENDER_PNG"] != nil { workspace.tool = .highlight }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let pdf = try XCTUnwrap(workspace.pdfView)
        XCTAssertTrue(pdf.scaleFactor.isFinite && pdf.scaleFactor > 0.05, "scale \(pdf.scaleFactor)")
        XCTAssertFalse(pdf.visiblePages.isEmpty)
        XCTAssertGreaterThan(pdf.bounds.width, 300)
        XCTAssertEqual(workspace.reader.fit, .page)
        XCTAssertLessThan(pdf.scaleFactor, 1.2)
        if ProcessInfo.processInfo.environment["FOLIO_RENDER_PNG"] != nil {
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/folio-readerfix/view.png"))
        }
    }
}

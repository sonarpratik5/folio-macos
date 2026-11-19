import XCTest
import PDFKit
import AppKit
import FolioCore
@testable import FolioMac

final class SkimWorkspaceTests: XCTestCase {
    @MainActor
    func testMarginGuidesBelongOnlyToEnabledSkimRoles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root); workspace.sample()
        let document = try XCTUnwrap(workspace.document)
        let page = try XCTUnwrap(document.page(at: 0))
        let rect = CGRect(x: 60, y: 200, width: 200, height: 14)
        for type in [PDFAnnotationSubtype.highlight, .underline, .text] {
            page.addAnnotation(PDFAnnotation(bounds: rect, forType: type, withProperties: nil))
        }
        let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 900, height: 900))
        view.workspace = workspace; view.document = document; view.scaleFactor = 1
        view.layoutSubtreeIfNeeded()
        let guides = MarginMarksView(frame: view.bounds); guides.pdfView = view
        XCTAssertTrue(guides.guides(on: page).isEmpty, "Saved marks have no edge indicators")
        workspace.skimEnabled = true
        XCTAssertTrue(guides.guides(on: page).isEmpty, "Skim must not pick up saved annotations")
        workspace.skimMarks = SkimFacet.allCases.map { SkimMark(page: page, facet: $0, rects: [rect]) }
        for rotation in [0, 90, 180, 270] {
            page.rotation = rotation
            view.layoutSubtreeIfNeeded()
            let rendered = guides.guides(on: page)
            XCTAssertEqual(rendered.count, 1)
            XCTAssertEqual(rendered.first?.label, "Goal / Method / Result")
            XCTAssertTrue(rendered.allSatisfy { $0.labelRect.width > 0 && $0.labelRect.height > 0 })
        }
        workspace.toggleSkimFacet(.method)
        XCTAssertEqual(guides.guides(on: page).first?.label, "Goal / Result")
        let otherDocument = PDFDocument(); let otherPage = PDFPage(); otherDocument.insert(otherPage, at: 0)
        XCTAssertTrue(guides.guides(on: otherPage).isEmpty)
        workspace.clearSkim()
        XCTAssertTrue(guides.guides(on: page).isEmpty)
    }

    @MainActor
    func testSkimInferenceLeavesPDFNotesAndHistoryUntouched() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: SkimClassifier.modelDirectory.appendingPathComponent("AdaptedMiniLM.mlmodelc").path),
                          "Adapted Skim weights are not tracked; export the model to verify inference integration.")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root); workspace.sample()
        let document = try XCTUnwrap(workspace.document)
        let managed = try XCTUnwrap(workspace.repository?.documentURL(for: XCTUnwrap(workspace.activeID)))
        let bytes = try Data(contentsOf: managed)
        let counts = (0..<document.pageCount).map { document.page(at: $0)!.annotations.count }
        let depth = workspace.editHistory?.depth
        workspace.toggleSkim()
        await workspace.skimTask?.value
        XCTAssertTrue(workspace.skimEnabled)
        XCTAssertFalse(workspace.skimLoading)
        XCTAssertNil(workspace.skimError)
        XCTAssertFalse(workspace.skimMarks.isEmpty)
        for mark in workspace.skimMarks {
            XCTAssertTrue(mark.page.document === document)
            XCTAssertTrue(mark.rects.allSatisfy { mark.page.bounds(for: .cropBox).contains($0) })
        }
        XCTAssertEqual((0..<document.pageCount).map { document.page(at: $0)!.annotations.count }, counts)
        XCTAssertEqual(workspace.editHistory?.depth, depth)
        XCTAssertTrue(workspace.notes.isEmpty)
        XCTAssertEqual(try Data(contentsOf: managed), bytes)
        workspace.toggleSkimFacet(.method)
        XCTAssertFalse(workspace.skimFacets.contains(.method))
        workspace.toggleSkim()
        XCTAssertFalse(workspace.skimEnabled)
        XCTAssertTrue(workspace.skimMarks.isEmpty)
    }

    @MainActor
    func testDocumentSwitchAndLibraryCancelStaleSkimWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root); workspace.sample()
        workspace.toggleSkim()
        let oldTask = workspace.skimTask
        workspace.open(try XCTUnwrap(workspace.activePaper))
        await oldTask?.value
        XCTAssertFalse(workspace.skimEnabled)
        XCTAssertFalse(workspace.skimLoading)
        XCTAssertTrue(workspace.skimMarks.isEmpty)
        workspace.toggleSkim()
        let nextTask = workspace.skimTask
        workspace.showLibrary()
        await nextTask?.value
        XCTAssertFalse(workspace.skimEnabled)
        XCTAssertTrue(workspace.skimMarks.isEmpty)
        XCTAssertNil(workspace.skimError)
    }

    @MainActor
    func testWritingPageChangeCancelsSkimBeforeGeometryCanBecomeStale() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root); workspace.sample()
        workspace.toggleSkim()
        let oldTask = workspace.skimTask
        workspace.insertWritingPage(after: 1)
        await oldTask?.value
        XCTAssertFalse(workspace.skimEnabled)
        XCTAssertTrue(workspace.skimMarks.isEmpty)
        XCTAssertNil(workspace.skimError)
    }
}

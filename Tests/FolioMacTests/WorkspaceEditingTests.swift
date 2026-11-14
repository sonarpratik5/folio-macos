import XCTest
import PDFKit
import AppKit
import FolioCore
@testable import FolioMac

final class WorkspaceEditingTests: XCTestCase {
    @MainActor
    private func withWorkspace(_ body: (Workspace, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        XCTAssertNil(workspace.errorMessage)
        try body(workspace, root)
    }

    @MainActor
    func testTextCreateEditColorResizeDeleteUndoRedoAndReopen() async throws {
        try withWorkspace { workspace, _ in
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            workspace.beginText(on: page, at: CGPoint(x: 80, y: 600))
            let draft = try XCTUnwrap(workspace.editor)
            workspace.saveEditor(draft, text: "My reading note\nSecond line", size: 16)
            XCTAssertNil(workspace.editor)
            XCTAssertEqual(workspace.selectedAnnotation?.type, "FreeText")
            XCTAssertTrue(workspace.notes.isEmpty)
            workspace.recolor("blue")
            workspace.resizeFont(24)
            let text = try XCTUnwrap(workspace.selectedAnnotation)
            XCTAssertEqual(text.font?.pointSize, 24)
            workspace.move(text, to: CGRect(x: 110, y: 400, width: 150, height: 100))
            let moved = try XCTUnwrap(workspace.selectedAnnotation)
            XCTAssertEqual(moved.bounds.minX, 110)
            workspace.edit(moved)
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Changed idea", size: 20)
            workspace.deleteSelection()
            XCTAssertFalse(page.annotations.contains { $0.type == "FreeText" })
            workspace.undoAnnotation()
            XCTAssertEqual(page.annotations.first { $0.type == "FreeText" }?.contents, "Changed idea")
            workspace.redoAnnotation()
            XCTAssertFalse(page.annotations.contains { $0.type == "FreeText" })
            workspace.undoAnnotation()
            let paper = try XCTUnwrap(workspace.activePaper)
            workspace.open(paper)
            XCTAssertFalse(workspace.canUndo)
            XCTAssertEqual(workspace.document?.page(at: 0)?.annotations.first { $0.type == "FreeText" }?.contents, "Changed idea")
            let reopenedText = workspace.document?.page(at: 0)?.annotations.first { $0.type == "FreeText" }
            XCTAssertEqual(reopenedText?.font?.pointSize, 20)
        }
    }

    @MainActor
    func testCrossPagePassageNoteRecolorEditEraseAndAllUndoSteps() async throws {
        try withWorkspace { workspace, _ in
            let document = try XCTUnwrap(workspace.document)
            let first = try XCTUnwrap(document.findString("Select", withOptions: []).first ?? document.findString("Choose Highlight", withOptions: []).first)
            let last = try XCTUnwrap(document.findString("Follow the evidence", withOptions: []).last)
            let selection = PDFSelection(document: document); selection.add(first); selection.add(last)
            workspace.beginNote(selection: selection)
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Compare these passages", size: 16)
            XCTAssertEqual(workspace.notes.count, 1)
            let note = try XCTUnwrap(workspace.selectedAnnotation)
            let members = PDFEditing.members(of: note, in: document)
            XCTAssertGreaterThanOrEqual(members.count, 3)
            XCTAssertGreaterThanOrEqual(Set(members.map { document.index(for: $0.0) }).count, 2)
            workspace.recolor("pink")
            let recolored = try XCTUnwrap(workspace.selectedAnnotation)
            XCTAssertEqual(PDFEditing.members(of: recolored, in: document).count, members.count)
            workspace.edit(recolored)
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "An edited question", size: 16)
            workspace.erase([try XCTUnwrap(workspace.selectedAnnotation)])
            XCTAssertTrue(workspace.notes.isEmpty)
            for _ in 0..<4 {
                workspace.undoAnnotation(); XCTAssertNil(workspace.errorMessage)
                let saved = try XCTUnwrap(PDFDocument(data: Data(contentsOf: workspace.repository!.documentURL(for: workspace.activeID!))))
                XCTAssertEqual(PDFNotes.read(from: saved).map(\.body), workspace.notes.map(\.body))
                for index in 0..<saved.pageCount {
                    let annotations = saved.page(at: index)!.annotations
                    XCTAssertLessThanOrEqual(annotations.filter { $0.type == "Popup" }.count, annotations.filter { $0.type == "Text" }.count)
                }
            }
            XCTAssertTrue(workspace.notes.isEmpty)
            XCTAssertFalse(workspace.canUndo)
            for _ in 0..<4 {
                workspace.redoAnnotation(); XCTAssertNil(workspace.errorMessage)
                let saved = try XCTUnwrap(PDFDocument(data: Data(contentsOf: workspace.repository!.documentURL(for: workspace.activeID!))))
                XCTAssertEqual(PDFNotes.read(from: saved).map(\.body), workspace.notes.map(\.body))
            }
            XCTAssertTrue(workspace.notes.isEmpty)
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.notes.first?.body, "An edited question")
            let current = try XCTUnwrap(workspace.notes.first?.annotation)
            XCTAssertEqual(PDFEditing.members(of: current, in: document).count, members.count)
        }
    }

    @MainActor
    func testCancelNoopFailedSaveAndDocumentSwitch() async throws {
        try withWorkspace { workspace, root in
            let document = try XCTUnwrap(workspace.document), page = try XCTUnwrap(workspace.document?.page(at: 0))
            workspace.beginText(on: page, at: CGPoint(x: 60, y: 500))
            workspace.editor = nil
            XCTAssertFalse(workspace.canUndo)
            workspace.beginNote(on: page)
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Written note", size: 16)
            let note = try XCTUnwrap(workspace.selectedAnnotation)
            workspace.edit(note)
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Written note", size: 16)
            workspace.undoAnnotation()
            XCTAssertTrue(workspace.notes.isEmpty)
            XCTAssertFalse(workspace.canUndo) // unchanged editor did not add history
            workspace.redoAnnotation()
            let managed = try XCTUnwrap(workspace.repository?.documentURL(for: XCTUnwrap(workspace.activeID)))
            let preserved = root.appendingPathComponent("preserved.pdf")
            try FileManager.default.moveItem(at: managed, to: preserved)
            try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
            workspace.select(try XCTUnwrap(workspace.notes.first?.annotation))
            workspace.deleteSelection()
            XCTAssertNotNil(workspace.errorMessage)
            XCTAssertTrue(workspace.saveFailed)
            XCTAssertEqual(workspace.notes.first?.body, "Written note")
            XCTAssertTrue(workspace.canUndo)
            try FileManager.default.removeItem(at: managed)
            try FileManager.default.moveItem(at: preserved, to: managed)
            workspace.errorMessage = nil
            workspace.undoAnnotation()
            XCTAssertFalse(workspace.saveFailed)
            XCTAssertTrue(workspace.notes.isEmpty)
            workspace.sample()
            XCTAssertFalse(workspace.canUndo)
            workspace.beginText(on: page, at: CGPoint(x: 40, y: 400)) // stale page rejected
            XCTAssertNil(workspace.editor)
            XCTAssertTrue(document !== workspace.document)
        }
    }
}

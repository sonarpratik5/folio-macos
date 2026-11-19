import XCTest
import PDFKit
import AppKit
@testable import FolioCore
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

    /// Count actual PDFKit traversal so this verifies avoided work, not wall-clock noise.
    private final class CountingNotePage: PDFPage {
        var annotationReads = 0
        override var annotations: [PDFAnnotation] {
            annotationReads += 1
            return super.annotations
        }
    }

    @MainActor
    func testNotesReuseScanUntilDocumentOrRevisionChanges() throws {
        try withWorkspace { workspace, _ in
            let document = try XCTUnwrap(workspace.document)
            let counted = CountingNotePage()
            let annotation = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 20, height: 20), forType: .text, withProperties: nil)
            annotation.contents = "Cached comment"
            counted.addAnnotation(annotation)
            document.insert(counted, at: document.pageCount)
            workspace.revision += 1
            counted.annotationReads = 0
            XCTAssertEqual(workspace.notes.last?.body, "Cached comment")
            let initialReads = counted.annotationReads
            XCTAssertGreaterThan(initialReads, 0)
            for _ in 0..<100 {
                _ = workspace.notes
            }
            workspace.page = 2
            workspace.inspector.toggle()
            XCTAssertEqual(workspace.notes.last?.body, "Cached comment")
            XCTAssertEqual(counted.annotationReads, initialReads)

            annotation.contents = "Changed comment"
            workspace.revision += 1
            XCTAssertEqual(workspace.notes.last?.body, "Changed comment")
            XCTAssertGreaterThan(counted.annotationReads, initialReads)

            let session = workspace.documentSessionID
            workspace.open(try XCTUnwrap(workspace.activePaper))
            XCTAssertNotEqual(workspace.documentSessionID, session)
            XCTAssertFalse(workspace.notes.contains { $0.body == "Changed comment" })
        }
    }

    @MainActor
    func testCachedNotesFollowWritingPageInsertionUndoAndRedo() throws {
        try withWorkspace { workspace, _ in
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            workspace.beginNote(on: page)
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Follow this page", size: 16)
            XCTAssertEqual(workspace.notes.map(\.page), [1])
            workspace.insertWritingPage(after: 0)
            XCTAssertEqual(workspace.notes.map(\.page), [2])
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.notes.map(\.page), [1])
            workspace.redoAnnotation()
            XCTAssertEqual(workspace.notes.map(\.page), [2])
        }
    }

    @MainActor
    func testLatestHighlightReplacesPreviousThroughUndoRedoAndReopen() throws {
        try withWorkspace { workspace, _ in
            let document = try XCTUnwrap(workspace.document)
            let page = try XCTUnwrap(document.page(at: 0))
            let selection = try XCTUnwrap(document.findString("reading research", withOptions: []).first)
            let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 700))
            view.workspace = workspace; view.document = document; workspace.pdfView = view
            @MainActor func highlight(_ color: String) {
                workspace.markColor = color
                view.setCurrentSelection(selection, animate: false)
                workspace.markSelection(.highlight)
            }
            highlight("yellow")
            let originalColor = try XCTUnwrap(page.annotations.first { $0.type == "Highlight" }).color
            highlight("blue")
            XCTAssertNil(workspace.errorMessage)
            XCTAssertEqual(page.annotations.filter { $0.type == "Highlight" }.count, 1)
            let latestColor = try XCTUnwrap(page.annotations.first { $0.type == "Highlight" }).color
            XCTAssertNotEqual(originalColor, latestColor)
            workspace.undoAnnotation()
            XCTAssertEqual(page.annotations.filter { $0.type == "Highlight" }.count, 1)
            XCTAssertEqual(page.annotations.first { $0.type == "Highlight" }?.color, originalColor)
            workspace.redoAnnotation()
            highlight("blue") // repeating the same color must not darken the passage either
            XCTAssertEqual(page.annotations.filter { $0.type == "Highlight" }.count, 1)
            workspace.open(try XCTUnwrap(workspace.activePaper))
            let saved = try XCTUnwrap(workspace.document?.page(at: 0)).annotations.filter { $0.type == "Highlight" }
            XCTAssertEqual(saved.count, 1)
            let savedColor = try XCTUnwrap(saved.first?.color.usingColorSpace(.deviceRGB))
            let expectedColor = try XCTUnwrap(latestColor.usingColorSpace(.deviceRGB))
            XCTAssertEqual(savedColor.redComponent, expectedColor.redComponent, accuracy: 0.0001)
            XCTAssertEqual(savedColor.greenComponent, expectedColor.greenComponent, accuracy: 0.0001)
            XCTAssertEqual(savedColor.blueComponent, expectedColor.blueComponent, accuracy: 0.0001)
        }
    }

    @MainActor
    func testFailedHighlightReplacementRestoresEarlierHighlightAndCanRetry() throws {
        try withWorkspace { workspace, root in
            let document = try XCTUnwrap(workspace.document), page = try XCTUnwrap(document.page(at: 0))
            let selection = try XCTUnwrap(document.findString("reading research", withOptions: []).first)
            let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 700))
            view.workspace = workspace; view.document = document; workspace.pdfView = view
            view.setCurrentSelection(selection, animate: false)
            workspace.markSelection(.highlight)
            let originalColor = try XCTUnwrap(page.annotations.first { $0.type == "Highlight" }).color
            let managed = try XCTUnwrap(workspace.repository?.documentURL(for: XCTUnwrap(workspace.activeID)))
            let preserved = root.appendingPathComponent("preserved.pdf")
            try FileManager.default.moveItem(at: managed, to: preserved)
            try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
            workspace.markColor = "blue"
            view.setCurrentSelection(selection, animate: false)
            workspace.markSelection(.highlight)
            XCTAssertTrue(workspace.saveFailed)
            XCTAssertEqual(page.annotations.filter { $0.type == "Highlight" }.count, 1)
            XCTAssertEqual(page.annotations.first { $0.type == "Highlight" }?.color, originalColor)
            try FileManager.default.removeItem(at: managed)
            try FileManager.default.moveItem(at: preserved, to: managed)
            workspace.markSelection(.highlight)
            XCTAssertFalse(workspace.saveFailed)
            XCTAssertEqual(page.annotations.filter { $0.type == "Highlight" }.count, 1)
            XCTAssertNotEqual(page.annotations.first { $0.type == "Highlight" }?.color, originalColor)
            workspace.undoAnnotation()
            XCTAssertEqual(page.annotations.first { $0.type == "Highlight" }?.color, originalColor)
        }
    }

    @MainActor
    func testNoteImageOnlyChangesAndAttachmentOnlyNotesSurviveReopen() throws {
        try withWorkspace { workspace, _ in
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            let image = NSImage(size: CGSize(width: 8, height: 8), flipped: false) { rect in
                NSColor.red.setFill(); rect.fill(); return true
            }
            let name = try XCTUnwrap(workspace.addNoteImage(image))
            workspace.beginNote(on: page)
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Keep this comment", size: 16)
            workspace.edit(try XCTUnwrap(workspace.notes.first?.annotation))
            workspace.pendingEditorImages = [name]
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Keep this comment", size: 16)
            XCTAssertEqual(workspace.notes.first?.images, [name])
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.notes.first?.images, [])
            workspace.redoAnnotation()
            XCTAssertEqual(workspace.notes.first?.images, [name])
            workspace.edit(try XCTUnwrap(workspace.notes.first?.annotation))
            workspace.pendingEditorImages = []
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Keep this comment", size: 16)
            XCTAssertEqual(workspace.notes.first?.images, [])
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.notes.first?.images, [name])
            workspace.edit(try XCTUnwrap(workspace.notes.first?.annotation))
            workspace.pendingEditorText = ""
            XCTAssertTrue(workspace.finishEditorIfNeeded())
            XCTAssertEqual(workspace.notes.first?.body, "")
            XCTAssertEqual(workspace.notes.first?.images, [name])
            let paper = try XCTUnwrap(workspace.activePaper)
            workspace.open(paper)
            XCTAssertEqual(workspace.notes.count, 1)
            XCTAssertEqual(workspace.notes.first?.body, "")
            XCTAssertEqual(workspace.notes.first?.images, [name])
            XCTAssertNotNil(workspace.noteImage(name))
        }
    }

    @MainActor
    func testFailedExistingEditRetriesWithoutDuplicatingAnnotation() throws {
        try withWorkspace { workspace, root in
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            workspace.beginNote(on: page)
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Original comment", size: 16)
            workspace.edit(try XCTUnwrap(workspace.notes.first?.annotation))
            let draft = try XCTUnwrap(workspace.editor)
            workspace.pendingEditorText = "Revised comment"
            let managed = try XCTUnwrap(workspace.repository?.documentURL(for: XCTUnwrap(workspace.activeID)))
            let preserved = root.appendingPathComponent("preserved.pdf")
            try FileManager.default.moveItem(at: managed, to: preserved)
            try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
            workspace.saveEditor(draft, text: "Revised comment", size: 16)
            XCTAssertNotNil(workspace.editor)
            XCTAssertTrue(workspace.saveFailed)
            XCTAssertEqual(workspace.notes.map(\.body), ["Original comment"])
            // A failed save restores fresh annotation snapshots; never return a cached detached object.
            XCTAssertTrue(workspace.notes.first?.annotation.page === page)
            try FileManager.default.removeItem(at: managed)
            try FileManager.default.moveItem(at: preserved, to: managed)
            // The popover still owns the original draft, so retry that same value.
            workspace.saveEditor(draft, text: "Revised comment", size: 16)
            XCTAssertNil(workspace.editor)
            XCTAssertFalse(workspace.saveFailed)
            XCTAssertEqual(workspace.notes.map(\.body), ["Revised comment"])
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.notes.map(\.body), ["Original comment"])
        }
    }

    @MainActor
    func testEmptyTextDeletionFailureKeepsDraftAndBlocksNavigation() throws {
        try withWorkspace { workspace, root in
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            workspace.beginText(on: page, at: CGPoint(x: 60, y: 500))
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Delete this box", size: 16)
            workspace.edit(try XCTUnwrap(workspace.selectedAnnotation))
            workspace.pendingEditorText = ""
            let managed = try XCTUnwrap(workspace.repository?.documentURL(for: XCTUnwrap(workspace.activeID)))
            let preserved = root.appendingPathComponent("preserved.pdf")
            try FileManager.default.moveItem(at: managed, to: preserved)
            try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: false)
            XCTAssertFalse(workspace.finishEditorIfNeeded())
            XCTAssertNotNil(workspace.editor)
            XCTAssertTrue(workspace.saveFailed)
            XCTAssertEqual(page.annotations.filter { $0.type == "FreeText" }.count, 1)
            try FileManager.default.removeItem(at: managed)
            try FileManager.default.moveItem(at: preserved, to: managed)
            XCTAssertTrue(workspace.finishEditorIfNeeded())
            XCTAssertNil(workspace.editor)
            XCTAssertFalse(workspace.saveFailed)
            XCTAssertFalse(page.annotations.contains { $0.type == "FreeText" })
            workspace.undoAnnotation()
            XCTAssertEqual(page.annotations.first { $0.type == "FreeText" }?.contents, "Delete this box")
        }
    }

    @MainActor
    func testAttachmentOnlyNoteDraftRecoversAndSavesWithoutText() throws {
        try withWorkspace { workspace, root in
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            let image = NSImage(size: CGSize(width: 8, height: 8), flipped: false) { rect in
                NSColor.blue.setFill(); rect.fill(); return true
            }
            let name = try XCTUnwrap(workspace.addNoteImage(image))
            workspace.beginNote(on: page)
            let draft = try XCTUnwrap(workspace.editor)
            workspace.pendingEditorImages = [name]
            workspace.persistNoteDraft(draft, text: "")
            let recovered = Workspace(libraryRoot: root)
            recovered.open(try XCTUnwrap(workspace.activePaper))
            XCTAssertNotNil(recovered.editor)
            XCTAssertEqual(recovered.pendingEditorImages, [name])
            XCTAssertTrue(recovered.finishEditorIfNeeded())
            XCTAssertEqual(recovered.notes.first?.images, [name])
            XCTAssertEqual(recovered.notes.first?.body, "")
        }
    }

    @MainActor
    func testRendererHiddenTextStaysVisibleThroughHistoryAndReplacement() throws {
        try withWorkspace { workspace, _ in
            let document = try XCTUnwrap(workspace.document), page = try XCTUnwrap(document.page(at: 0))
            let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 700))
            view.workspace = workspace; view.document = document; workspace.pdfView = view
            workspace.beginText(on: page, at: CGPoint(x: 70, y: 500))
            workspace.saveEditor(try XCTUnwrap(workspace.editor), text: "Visible after undo", size: 16)
            let original = try XCTUnwrap(page.annotations.first { $0.type == "FreeText" })
            view.hideRotatedTexts() // same transient model flag used by the reader's vector renderer
            XCTAssertFalse(original.shouldDisplay)
            workspace.erase([original])
            workspace.undoAnnotation()
            view.restoreRotatedTexts()
            XCTAssertTrue(try XCTUnwrap(page.annotations.first { $0.type == "FreeText" }).shouldDisplay)
            let managed = try XCTUnwrap(workspace.repository?.documentURL(for: XCTUnwrap(workspace.activeID)))
            let reopened = try XCTUnwrap(PDFDocument(data: Data(contentsOf: managed)))
            XCTAssertTrue(try XCTUnwrap(reopened.page(at: 0)?.annotations.first { $0.type == "FreeText" }).shouldDisplay)
            // Recolor/move copy the live object before the history transaction.
            let restored = try XCTUnwrap(page.annotations.first { $0.type == "FreeText" })
            workspace.select(restored); view.hideRotatedTexts()
            workspace.recolor("blue")
            view.restoreRotatedTexts()
            XCTAssertTrue(try XCTUnwrap(workspace.selectedAnnotation).shouldDisplay)
            view.hideRotatedTexts()
            workspace.move(try XCTUnwrap(workspace.selectedAnnotation), to: CGRect(x: 90, y: 400, width: 200, height: 40))
            view.restoreRotatedTexts()
            XCTAssertTrue(try XCTUnwrap(workspace.selectedAnnotation).shouldDisplay)
            workspace.undoAnnotation(); workspace.redoAnnotation()
            view.restoreRotatedTexts()
            XCTAssertTrue(try XCTUnwrap(page.annotations.first { $0.type == "FreeText" }).shouldDisplay)
        }
    }

    @MainActor
    func testFolderBrowsingRecentVisitsRefreshAndRelaunch() throws {
        try withWorkspace { workspace, root in
            let sourceFolder = root.appendingPathComponent("Research")
            try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
            let source = sourceFolder.appendingPathComponent("First.pdf")
            let bytes = try XCTUnwrap(workspace.document?.dataRepresentation())
            try bytes.write(to: source)
            try bytes.write(to: sourceFolder.appendingPathComponent("Second.PDF"))
            try Data("not a PDF".utf8).write(to: sourceFolder.appendingPathComponent("readme.txt"))
            let nested = sourceFolder.appendingPathComponent("Nested")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try bytes.write(to: nested.appendingPathComponent("Child.pdf"))
            let priorRecent = workspace.recentPapers.map(\.id)
            workspace.openFolder(sourceFolder)
            XCTAssertNil(workspace.errorMessage)
            XCTAssertFalse(workspace.reading)
            XCTAssertEqual(workspace.libraryPapers.count, 3)
            XCTAssertEqual(workspace.recentPapers.map(\.id), priorRecent)
            let first = try XCTUnwrap(workspace.libraryPapers.first)
            let second = try XCTUnwrap(workspace.libraryPapers.last)
            workspace.open(first, at: 2)
            workspace.open(second)
            workspace.open(first)
            XCTAssertEqual(Array(workspace.recentPapers.prefix(2)).map(\.id), [first.id, second.id])
            XCTAssertEqual(workspace.page, 2)
            workspace.openFolder(sourceFolder)
            XCTAssertEqual(workspace.libraryPapers.count, 3)
            XCTAssertEqual(try Data(contentsOf: source), bytes)
            try bytes.write(to: sourceFolder.appendingPathComponent("Third.pdf"))
            workspace.openFolder(sourceFolder)
            XCTAssertEqual(workspace.libraryPapers.count, 4)
            XCTAssertEqual(workspace.recentPapers.first?.id, first.id)
            let reopened = Workspace(libraryRoot: root)
            XCTAssertEqual(reopened.folders, [sourceFolder.path, nested.path])
            XCTAssertEqual(reopened.recentPapers.map(\.id), workspace.recentPapers.map(\.id))
            reopened.selectFolder(sourceFolder.path)
            XCTAssertEqual(reopened.libraryPapers.count, 4)
            reopened.navigate(to: .opened)
            XCTAssertNil(reopened.selectedFolder)
            XCTAssertEqual(reopened.libraryPapers.map(\.id), reopened.recentPapers.map(\.id))
            reopened.removePaper(first)
            XCTAssertFalse(reopened.recentPapers.contains { $0.id == first.id })
            let emptyFolder = root.appendingPathComponent("Empty")
            try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
            reopened.openFolder(emptyFolder)
            XCTAssertTrue(reopened.libraryPapers.isEmpty)
            XCTAssertEqual(Workspace(libraryRoot: root).folders.count, 3)
        }
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
    @MainActor
    func testStructuralPagesKeepManifestValidAcrossUndoRedoAndRelaunch() throws {
        try withWorkspace { workspace, root in
            let count = try XCTUnwrap(workspace.document?.pageCount)
            let repository = try XCTUnwrap(workspace.repository)
            workspace.go(to: count); workspace.toggleStar()
            workspace.insertWritingPage(after: nil)
            XCTAssertEqual(workspace.activePaper?.pageCount, count + 1)
            XCTAssertEqual(workspace.activePaper?.currentPage, count + 1)
            XCTAssertEqual(try repository.load(), workspace.papers)
            let reloaded = Workspace(libraryRoot: root)
            XCTAssertNil(reloaded.errorMessage)
            reloaded.open(try XCTUnwrap(reloaded.papers.first))
            XCTAssertEqual(reloaded.page, count + 1)
            let assistant = PaperAssistantModel()
            assistant.load(root: root, record: try XCTUnwrap(reloaded.activePaper))
            XCTAssertNil(assistant.error)
            XCTAssertEqual(assistant.paper?.pageCount, count + 1)
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.activePaper?.pageCount, count)
            XCTAssertEqual(try repository.load(), workspace.papers)
            workspace.redoAnnotation()
            XCTAssertEqual(workspace.activePaper?.pageCount, count + 1)
            XCTAssertEqual(try repository.load(), workspace.papers)
            workspace.undoAnnotation()
            workspace.insertWritingPage(after: 0)
            XCTAssertEqual(workspace.activePaper?.starredPages, [count + 1])
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.activePaper?.starredPages, [count])
            workspace.redoAnnotation()
            XCTAssertEqual(workspace.activePaper?.starredPages, [count + 1])
            XCTAssertNil(Workspace(libraryRoot: root).errorMessage)
        }
    }

    @MainActor
    func testStructuralSaveFailureKeepsMetadataHistoryAndAllowsRetry() throws {
        try withWorkspace { workspace, _ in
            let repository = try XCTUnwrap(workspace.repository)
            let document = try XCTUnwrap(workspace.document)
            let record = try XCTUnwrap(workspace.activePaper)
            let original = try Data(contentsOf: repository.documentURL(for: record.id))
            var failed = false
            repository.writeAtomically = { data, url in
                if url.lastPathComponent == "library.json", !failed {
                    failed = true; throw CocoaError(.fileWriteOutOfSpace)
                }
                try data.write(to: url, options: .atomic)
            }
            workspace.insertWritingPage(after: nil)
            XCTAssertTrue(failed)
            XCTAssertNotNil(workspace.errorMessage)
            XCTAssertEqual(document.pageCount, record.pageCount)
            XCTAssertEqual(workspace.activePaper, record)
            XCTAssertTrue(workspace.writingUndo.isEmpty)
            XCTAssertEqual(try Data(contentsOf: repository.documentURL(for: record.id)), original)
            workspace.insertWritingPage(after: nil)
            XCTAssertEqual(document.pageCount, record.pageCount + 1)
            XCTAssertEqual(try repository.load(), workspace.papers)
        }
    }

    @MainActor
    func testRemovalFlushesWritingAndClearsPaperStateBeforeOpeningAnother() throws {
        try withWorkspace { workspace, _ in
            let first = try XCTUnwrap(workspace.activePaper)
            workspace.sample()
            let other = try XCTUnwrap(workspace.activePaper)
            workspace.open(first)
            workspace.pendingWriting = (try XCTUnwrap(workspace.document?.page(at: 0)), "Pending input")
            workspace.ensureAIStore()
            workspace.showWriting = true
            workspace.removePaper(first)
            XCTAssertNil(workspace.activeID)
            XCTAssertNil(workspace.pendingWriting)
            XCTAssertNil(workspace.aiStore)
            XCTAssertTrue(workspace.writingUndo.isEmpty)
            XCTAssertTrue(workspace.writingRedo.isEmpty)
            XCTAssertFalse(workspace.showWriting)
            workspace.open(other)
            XCTAssertEqual(workspace.activeID, other.id)
            XCTAssertTrue(workspace.reading)
        }
    }

    @MainActor
    func testRemovalAbortsWhenPendingWritingCannotSave() throws {
        try withWorkspace { workspace, root in
            let record = try XCTUnwrap(workspace.activePaper)
            let page = try XCTUnwrap(workspace.document?.page(at: 0))
            let documents = root.appendingPathComponent("Documents")
            let held = root.appendingPathComponent("Documents-held")
            try FileManager.default.moveItem(at: documents, to: held)
            try Data("block".utf8).write(to: documents)
            workspace.pendingWriting = (page, "Retain this input")
            workspace.removePaper(record)
            XCTAssertEqual(workspace.activeID, record.id)
            XCTAssertEqual(workspace.pendingWriting?.text, "Retain this input")
            XCTAssertNotNil(workspace.errorMessage)
            XCTAssertEqual(workspace.papers.count, 1)
            try FileManager.default.removeItem(at: documents)
            try FileManager.default.moveItem(at: held, to: documents)
            workspace.removePaper(record)
            XCTAssertTrue(workspace.papers.isEmpty)
            XCTAssertNil(workspace.pendingWriting)
        }
    }

    @MainActor
    func testStructuralEditsAndReopenReplaceAIStateWithoutSending() throws {
        try withWorkspace { workspace, _ in
            let original = try XCTUnwrap(workspace.ensureAIStore())
            workspace.insertWritingPage(after: nil)
            let afterInsert = try XCTUnwrap(workspace.activeAIStore)
            XCTAssertFalse(original === afterInsert)
            XCTAssertNil(afterInsert.assistant.paper)
            workspace.undoAnnotation()
            let afterUndo = try XCTUnwrap(workspace.activeAIStore)
            XCTAssertFalse(afterInsert === afterUndo)
            workspace.open(try XCTUnwrap(workspace.activePaper))
            XCTAssertNil(workspace.activeAIStore)
            XCTAssertFalse(try XCTUnwrap(workspace.ensureAIStore()) === afterUndo)
        }
    }

    @MainActor
    func testFailedStructuralUndoRedoRetainHistoryForIdenticalRetry() throws {
        try withWorkspace { workspace, _ in
            let repository = try XCTUnwrap(workspace.repository)
            let count = try XCTUnwrap(workspace.document?.pageCount)
            workspace.insertWritingPage(after: nil)
            var failNextManifest = true
            repository.writeAtomically = { data, url in
                if url.lastPathComponent == "library.json", failNextManifest {
                    failNextManifest = false; throw CocoaError(.fileWriteOutOfSpace)
                }
                try data.write(to: url, options: .atomic)
            }
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.document?.pageCount, count + 1)
            XCTAssertEqual(workspace.activePaper?.pageCount, count + 1)
            XCTAssertEqual(workspace.writingUndo.count, 1)
            XCTAssertTrue(workspace.writingRedo.isEmpty)
            XCTAssertEqual(try repository.load(), workspace.papers)
            workspace.undoAnnotation()
            XCTAssertEqual(workspace.document?.pageCount, count)
            failNextManifest = true
            workspace.redoAnnotation()
            XCTAssertEqual(workspace.document?.pageCount, count)
            XCTAssertEqual(workspace.activePaper?.pageCount, count)
            XCTAssertTrue(workspace.writingUndo.isEmpty)
            XCTAssertEqual(workspace.writingRedo.count, 1)
            XCTAssertEqual(try repository.load(), workspace.papers)
            workspace.redoAnnotation()
            XCTAssertEqual(workspace.document?.pageCount, count + 1)
            XCTAssertEqual(try repository.load(), workspace.papers)
        }
    }

}

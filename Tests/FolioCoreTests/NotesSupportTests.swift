import XCTest
import PDFKit
@testable import FolioCore

final class NotesSupportTests: XCTestCase {
    private func tempRoot() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("folio-notes-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testImageStoreRoundTripAndRejectsPaths() throws {
        let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteImageStore(root: root), paper = UUID()
        let name = try store.save(Data([1, 2, 3]), paper: paper)
        XCTAssertTrue(NoteImageStore.isValid(name))
        XCTAssertEqual(store.data(name, paper: paper), Data([1, 2, 3]))
        XCTAssertNil(store.url("../evil.png", paper: paper))
        store.remove(name, paper: paper)
        XCTAssertNil(store.data(name, paper: paper))
    }

    func testDraftPersistsAndClears() {
        let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteDraftStore(root: root), paper = UUID()
        let draft = NoteDraftRecord(page: 2, bounds: CGRect(x: 10, y: 20, width: 22, height: 22), isFreeText: false, text: "half-written", quote: "q")
        store.save(draft, paper: paper)
        XCTAssertEqual(store.load(paper: paper), draft)
        store.clear(paper: paper)
        XCTAssertNil(store.load(paper: paper))
    }

    func testAttachmentOnlyDraftRestoresButEmptyOrInvalidAttachmentDoesNot() {
        let root = tempRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = NoteDraftStore(root: root), paper = UUID()
        let name = UUID().uuidString + ".png"
        let draft = NoteDraftRecord(page: 1, bounds: CGRect(x: 10, y: 20, width: 22, height: 22),
                                    isFreeText: false, text: "", quote: "", images: [name])
        store.save(draft, paper: paper)
        XCTAssertEqual(store.load(paper: paper), draft)
        for invalid in [NoteDraftRecord(page: 1, bounds: draft.bounds, isFreeText: false, text: " ", quote: ""),
                        NoteDraftRecord(page: 1, bounds: draft.bounds, isFreeText: false, text: "", quote: "", images: ["../image.png"]),
                        NoteDraftRecord(page: 1, bounds: draft.bounds, isFreeText: true, text: "", quote: "", images: [name])] {
            store.save(invalid, paper: paper)
            XCTAssertNil(store.load(paper: paper))
        }
    }

    func testBlankPageInsertsAndSerializes() throws {
        let page = try XCTUnwrap(WritingPages.blankPage(size: CGSize(width: 612, height: 792)))
        let document = PDFDocument()
        document.insert(page, at: 0)
        XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 612, height: 792))
        XCTAssertNotNil(PDFDocument(data: try XCTUnwrap(document.dataRepresentation())))
        XCTAssertNil(WritingPages.blankPage(size: CGSize(width: 0, height: 10)))
    }

    func testNoteFilteringAndGrouping() {
        let document = PDFDocument()
        for _ in 0..<2 { document.insert(WritingPages.blankPage(size: CGSize(width: 300, height: 300))!, at: document.pageCount) }
        for (i, text) in ["alpha idea", "Beta result", "alpha again"].enumerated() {
            let a = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 20, height: 20), forType: .text, withProperties: nil)
            a.contents = text; a.color = i == 1 ? .systemBlue : .systemYellow
            document.page(at: i == 2 ? 1 : 0)!.addAnnotation(a)
        }
        let notes = PDFNotes.read(from: document)
        XCTAssertEqual(PDFNotes.filter(notes, query: "ALPHA").count, 2)
        XCTAssertEqual(PDFNotes.filter(notes, query: "", color: .systemBlue).count, 1)
        XCTAssertEqual(PDFNotes.grouped(notes).map(\.page), [1, 2])
    }
}

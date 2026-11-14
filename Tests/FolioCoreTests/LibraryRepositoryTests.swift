import XCTest
import PDFKit
import AppKit
@testable import FolioCore

final class LibraryRepositoryTests: XCTestCase {
    private var scratch: URL!
    private var repository: LibraryRepository!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = try LibraryRepository(root: scratch.appendingPathComponent("Library"))
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: scratch) }

    private func fixture() throws -> URL {
        let bytes = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(data: bytes as Data))
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Disposable fixture"]
        let url = scratch.appendingPathComponent("source.pdf")
        XCTAssertTrue(document.write(to: url))
        return url
    }

    func testEmptyLibrary() throws { XCTAssertTrue(try repository.load().isEmpty) }

    func testImportCopiesPDFAndRoundTripsReadingState() throws {
        let source = try fixture()
        let original = try Data(contentsOf: source)
        var paper = try repository.importPDF(from: source, existing: [])
        XCTAssertEqual(paper.title, "Disposable fixture")
        XCTAssertEqual(paper.pageCount, 1)
        XCTAssertEqual(try Data(contentsOf: repository.documentURL(for: paper.id)), original)
        paper.starredPages = [1]
        try repository.save([paper])
        XCTAssertEqual(try repository.load(), [paper])
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testPDFAnnotationsPersistWithoutChangingSourceOrPageSize() throws {
        let source = try fixture()
        let original = try Data(contentsOf: source)
        let paper = try repository.importPDF(from: source, existing: [])
        let document = try XCTUnwrap(PDFDocument(url: repository.documentURL(for: paper.id)))
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let note = PDFAnnotation(bounds: CGRect(x: 10, y: 20, width: 22, height: 22), forType: .text, withProperties: nil)
        note.contents = "A question about the evidence"
        page.addAnnotation(note)
        page.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 50, width: 80, height: 12), forType: .highlight, withProperties: nil))
        try repository.saveDocument(document, for: paper.id)
        let reopened = try XCTUnwrap(PDFDocument(url: repository.documentURL(for: paper.id)))
        XCTAssertEqual(PDFNotes.read(from: reopened).map(\.body), ["A question about the evidence"])
        let annotations = try XCTUnwrap(reopened.page(at: 0)).annotations
        // Some macOS versions also serialize a companion Popup for a Text comment.
        XCTAssertEqual(annotations.filter { $0.type == "Text" }.count, 1)
        XCTAssertEqual(annotations.filter { $0.type == "Highlight" }.count, 1)
        XCTAssertEqual(reopened.page(at: 0)?.bounds(for: .mediaBox), bounds)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testRejectsNonPDFWithoutCreatingLibraryEntry() throws {
        let source = scratch.appendingPathComponent("invalid.pdf")
        try Data("not a PDF".utf8).write(to: source)
        XCTAssertThrowsError(try repository.importPDF(from: source, existing: []))
        XCTAssertTrue(try repository.load().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: repository.root.appendingPathComponent("Documents").path).isEmpty)
    }

    func testCorruptManifestIsPreserved() throws {
        let manifest = repository.root.appendingPathComponent("library.json")
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: manifest)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: manifest), corrupt)
    }

    func testFutureSchemaIsRejected() throws {
        let manifest = repository.root.appendingPathComponent("library.json")
        let data = Data(#"{"schemaVersion":99,"papers":[]}"#.utf8)
        try data.write(to: manifest)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: manifest), data)
    }

    func testInvalidReadingPositionIsRejected() throws {
        var paper = PaperRecord(title: "Bad metadata", pageCount: 2)
        paper.currentPage = 99
        try repository.save([paper])
        XCTAssertThrowsError(try repository.load())
    }

    func testFailedManifestSaveRollsBackImportedCopy() throws {
        let source = try fixture()
        let manifest = repository.root.appendingPathComponent("library.json")
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        XCTAssertThrowsError(try repository.importPDF(from: source, existing: []))
        let files = try FileManager.default.contentsOfDirectory(atPath: repository.root.appendingPathComponent("Documents").path)
        XCTAssertTrue(files.isEmpty)
    }
}

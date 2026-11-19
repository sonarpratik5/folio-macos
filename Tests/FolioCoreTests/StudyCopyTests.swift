import XCTest
import AppKit
import PDFKit
@testable import FolioCore

final class StudyCopyTests: XCTestCase {
    func testWritingContinuationPaginatedWithoutChangingSource() throws {
        let document = PDFDocument()
        let page = try XCTUnwrap(WritingPages.blankPage(size: CGSize(width: 400, height: 500)))
        document.insert(page, at: 0)
        page.rotation = 90
        let note = PDFAnnotation(bounds: CGRect(x: 8, y: 8, width: 16, height: 16), forType: .text, withProperties: nil)
        note.contents = (1...250).map { "Line \($0): mathematical evidence and notes." }.joined(separator: "\n")
        note.setValue("1", forAnnotationKey: StudyCopy.writingKey)
        note.shouldDisplay = false; note.shouldPrint = false
        page.addAnnotation(note)
        let data = try StudyCopy.export(document, study: true, imageData: { _ in nil })
        let reopened = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(reopened.pageCount, 3)
        let repeated = try XCTUnwrap(PDFDocument(data: StudyCopy.export(reopened, study: true, imageData: { _ in nil })))
        XCTAssertEqual(repeated.pageCount, reopened.pageCount)
        XCTAssertEqual(reopened.page(at: 0)?.rotation, 90)
        XCTAssertTrue(reopened.string?.contains("Line 250:") == true)
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(page.rotation, 90)
        XCTAssertEqual(StudyCopy.writing(on: try XCTUnwrap(reopened.page(at: 0)))?.contents, note.contents)
        let normal = try XCTUnwrap(PDFDocument(data: StudyCopy.export(document, study: false, imageData: { _ in nil })))
        XCTAssertEqual(normal.pageCount, 1)
        XCTAssertEqual(PDFEditing.copy(note)?.value(forAnnotationKey: StudyCopy.writingKey) as? String, "1")
    }

    func testPortableImageSurvivesSerializationWithoutSidecarAndDoesNotMutateLiveAnnotation() throws {
        let document = PDFDocument()
        let page = try XCTUnwrap(WritingPages.blankPage(size: CGSize(width: 400, height: 500)))
        document.insert(page, at: 0)
        let image = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in NSColor.systemBlue.setFill(); rect.fill(); return true }
        let png = try XCTUnwrap(NoteImageStore.png(from: image))
        let name = UUID().uuidString + ".png"
        let note = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 20, height: 20), forType: .text, withProperties: nil)
        note.contents = "Diagram"; note.setValue(name, forAnnotationKey: PDFNotes.imagesKey); page.addAnnotation(note)
        let exported = try StudyCopy.export(document, study: false) { $0 == name ? png : nil }
        let reopened = try XCTUnwrap(PDFDocument(data: exported))
        XCTAssertEqual(reopened.pageCount, 2)
        let saved = try XCTUnwrap(reopened.page(at: 0)?.annotations.first)
        let images = StudyCopy.embeddedImages(in: saved)
        XCTAssertEqual(images[name].flatMap { Data(base64Encoded: $0) }, png)
        XCTAssertNil(note.value(forAnnotationKey: StudyCopy.embeddedImagesKey))
        XCTAssertEqual(document.pageCount, 1)
        let repeated = try XCTUnwrap(PDFDocument(data: StudyCopy.export(reopened, study: false, imageData: { _ in nil })))
        XCTAssertEqual(repeated.pageCount, reopened.pageCount)
        XCTAssertNotNil(PDFEditing.copy(saved)?.value(forAnnotationKey: StudyCopy.embeddedImagesKey))
        XCTAssertThrowsError(try StudyCopy.export(document, study: false, imageData: { _ in nil }))
    }
}

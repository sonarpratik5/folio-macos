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

    func testFoldersAndVisitsSurviveMetadataSavesAndRemoval() throws {
        let source = try fixture()
        let folder = source.deletingLastPathComponent().path
        try repository.save([], folders: [folder])
        var paper = try repository.importPDF(from: source, existing: [], folderPath: folder)
        XCTAssertNil(paper.lastVisit)
        XCTAssertEqual(paper.folderPath, folder)
        paper.visitedAt = Date(timeIntervalSince1970: 42)
        try repository.save([paper])
        XCTAssertEqual(try repository.load(), [paper])
        XCTAssertEqual(try repository.loadFolders(), [folder])
        _ = try repository.remove(paper.id, from: [paper])
        XCTAssertEqual(try repository.loadFolders(), [folder])
        XCTAssertTrue(try repository.load().isEmpty)
    }

    func testLegacyManifestWithoutFolderOrVisitFieldsLoads() throws {
        let source = try fixture()
        var paper = try repository.importPDF(from: source, existing: [])
        paper.lastOpened = paper.addedAt!.addingTimeInterval(10)
        try repository.save([paper])
        let manifest = repository.root.appendingPathComponent("library.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        json.removeValue(forKey: "folders")
        var records = try XCTUnwrap(json["papers"] as? [[String: Any]])
        records[0].removeValue(forKey: "sourcePath")
        json["papers"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: manifest)
        XCTAssertEqual(try repository.load().first?.lastVisit, paper.lastOpened)
        XCTAssertEqual(try repository.loadFolders(), [])
    }

    func testExportRejectsManagedPathsThroughSymlinkedParentsAndLibraryRoot() throws {
        let link = scratch.appendingPathComponent("Library-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repository.root)
        let managed = repository.documentURL(for: UUID())
        XCTAssertFalse(repository.allowsExport(to: managed))
        XCTAssertFalse(repository.allowsExport(to: repository.root))
        XCTAssertFalse(repository.allowsExport(to: link.appendingPathComponent("Documents/new.pdf")))
        let linkedRepository = try LibraryRepository(root: link)
        XCTAssertFalse(linkedRepository.allowsExport(to: managed))
        XCTAssertTrue(repository.allowsExport(to: scratch.appendingPathComponent("Library-export/new.pdf")))
        XCTAssertTrue(repository.allowsExport(to: scratch.appendingPathComponent("export.pdf")))

        let fileLink = scratch.appendingPathComponent("managed-link.pdf")
        try Data("preserved".utf8).write(to: managed)
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: managed)
        XCTAssertFalse(repository.allowsExport(to: fileLink))
        XCTAssertEqual(try Data(contentsOf: managed), Data("preserved".utf8))
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
        XCTAssertThrowsError(try repository.save([paper]))
        // Simulate an invalid file from an older version, bypassing the save boundary.
        try JSONEncoder().encode(LibrarySnapshot(papers: [paper])).write(to: repository.root.appendingPathComponent("library.json"))
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
    func testStructuralSaveRollsBackBothFilesWhenManifestWriteFailsAndRetries() throws {
        let source = try fixture()
        let originalSource = try Data(contentsOf: source)
        var record = try repository.importPDF(from: source, existing: [])
        let managed = repository.documentURL(for: record.id)
        let before = try Data(contentsOf: managed)
        let document = try XCTUnwrap(PDFDocument(data: before))
        document.insert(try XCTUnwrap(WritingPages.blankPage(size: CGSize(width: 300, height: 400))), at: 1)
        record.pageCount = 2; record.currentPage = 2; record.starredPages = [2]
        var failed = false
        repository.writeAtomically = { data, url in
            if url.lastPathComponent == "library.json", !failed {
                failed = true
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try data.write(to: url, options: .atomic)
        }
        XCTAssertThrowsError(try repository.saveStructure(document, for: record.id, papers: [record]))
        XCTAssertTrue(failed)
        XCTAssertEqual(try Data(contentsOf: managed), before)
        XCTAssertEqual(try repository.load().first?.pageCount, 1)
        try repository.saveStructure(document, for: record.id, papers: [record])
        XCTAssertEqual(try LibraryRepository(root: repository.root).load(), [record])
        XCTAssertEqual(PDFDocument(url: managed)?.pageCount, 2)
        XCTAssertEqual(try Data(contentsOf: source), originalSource)
    }

    func testInterruptedStructuralSaveRecoversBeforeOpeningLibrary() throws {
        let record = try repository.importPDF(from: fixture(), existing: [])
        let managed = repository.documentURL(for: record.id)
        let manifest = repository.root.appendingPathComponent("library.json")
        let originalPDF = try Data(contentsOf: managed)
        let originalManifest = try Data(contentsOf: manifest)
        let rollback = LibraryRepository.StructureRollback(paperID: record.id, document: originalPDF, manifest: originalManifest)
        let journal = repository.root.appendingPathComponent("structure-rollback.json")
        try JSONEncoder().encode(rollback).write(to: journal, options: .atomic)
        let document = try XCTUnwrap(PDFDocument(data: originalPDF))
        document.insert(try XCTUnwrap(WritingPages.blankPage(size: CGSize(width: 300, height: 400))), at: 1)
        try XCTUnwrap(document.dataRepresentation()).write(to: managed, options: .atomic)
        // A crash can occur after either replacement, including after the new manifest.
        var changed = record; changed.pageCount = 2; changed.currentPage = 2
        try JSONEncoder().encode(LibrarySnapshot(papers: [changed])).write(to: manifest, options: .atomic)
        let recovered = try LibraryRepository(root: repository.root)
        XCTAssertEqual(try recovered.load(), [record])
        XCTAssertEqual(try Data(contentsOf: managed), originalPDF)
        XCTAssertEqual(try Data(contentsOf: manifest), originalManifest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    func testMalformedStructuralJournalFailsClosedWithoutReplacingFiles() throws {
        let record = try repository.importPDF(from: fixture(), existing: [])
        let managed = repository.documentURL(for: record.id)
        let before = try Data(contentsOf: managed)
        let journal = repository.root.appendingPathComponent("structure-rollback.json")
        let invalid = Data("broken journal".utf8)
        try invalid.write(to: journal)
        XCTAssertThrowsError(try LibraryRepository(root: repository.root))
        XCTAssertThrowsError(try repository.save([record]))
        XCTAssertEqual(try Data(contentsOf: journal), invalid)
        XCTAssertEqual(try Data(contentsOf: managed), before)
    }

    func testRecoveryJournalSurvivesFailedRollbackAndRecoversAfterStorageRepair() throws {
        var record = try repository.importPDF(from: fixture(), existing: [])
        let before = try Data(contentsOf: repository.documentURL(for: record.id))
        let document = try XCTUnwrap(PDFDocument(data: before))
        document.insert(try XCTUnwrap(WritingPages.blankPage(size: CGSize(width: 300, height: 400))), at: 1)
        record.pageCount = 2; record.currentPage = 2
        repository.writeAtomically = { data, url in
            if url.lastPathComponent == "library.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
        XCTAssertThrowsError(try repository.saveStructure(document, for: record.id, papers: [record]))
        let journal = repository.root.appendingPathComponent("structure-rollback.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertThrowsError(try repository.save([record]))
        let recovered = try LibraryRepository(root: repository.root)
        XCTAssertEqual(try recovered.load().first?.pageCount, 1)
        XCTAssertEqual(try Data(contentsOf: recovered.documentURL(for: record.id)), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    }

    func testInvalidSaveNeverReplacesValidManifest() throws {
        let record = try repository.importPDF(from: fixture(), existing: [])
        let manifest = repository.root.appendingPathComponent("library.json")
        let before = try Data(contentsOf: manifest)
        var invalid = record; invalid.starredPages = [2]
        XCTAssertThrowsError(try repository.save([invalid]))
        XCTAssertThrowsError(try repository.save([record, record]))
        XCTAssertEqual(try Data(contentsOf: manifest), before)
    }

}

import XCTest
import FolioCore
@testable import FolioMac

final class PaperAssistantTests: XCTestCase {
    @MainActor
    func testInsightsDoesNotReplaceReaderOrWriteReadingPosition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioInsightsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let first = try XCTUnwrap(workspace.activePaper)
        workspace.sample()
        let activeID = workspace.activeID
        let document = workspace.document
        let manifest = try Data(contentsOf: root.appendingPathComponent("library.json"))
        workspace.present(.overview, for: first)
        XCTAssertFalse(workspace.reading)
        XCTAssertEqual(workspace.section, .insights)
        XCTAssertEqual(workspace.insightsPaperID, first.id)
        XCTAssertEqual(workspace.activeID, activeID)
        XCTAssertTrue(workspace.document === document)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), manifest)
        // Source navigation must open the inspected paper, even if another PDF was active.
        workspace.open(first, at: 2)
        XCTAssertTrue(workspace.reading)
        XCTAssertEqual(workspace.activeID, first.id)
        XCTAssertEqual(workspace.page, 2)
        workspace.navigate(to: .all)
        XCTAssertFalse(workspace.reading)
        XCTAssertEqual(workspace.section, .all)
    }

    @MainActor
    func testHomeAssistantLoadsManagedPDFWithoutOpeningReaderOrWritingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioAssistantModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let first = try XCTUnwrap(workspace.activePaper)
        workspace.sample()
        let activeID = workspace.activeID
        let document = workspace.document
        let repository = try XCTUnwrap(workspace.repository)
        let original = try Data(contentsOf: repository.documentURL(for: first.id))
        let manifest = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let model = PaperAssistantModel()
        model.load(root: root, record: first)
        XCTAssertNil(model.error)
        XCTAssertNotNil(model.paper)
        XCTAssertTrue(model.snapshot?.turns.isEmpty == true)
        XCTAssertNil(model.snapshot?.overview)
        XCTAssertEqual(workspace.activeID, activeID)
        XCTAssertTrue(workspace.document === document)
        XCTAssertEqual(try Data(contentsOf: repository.documentURL(for: first.id)), original)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), manifest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Assistant").path))
    }

    @MainActor
    func testMalformedHistoryDisablesAssistantAndPreservesFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioAssistantModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let record = try XCTUnwrap(workspace.activePaper)
        let directory = root.appendingPathComponent("Assistant")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(record.id.uuidString).appendingPathExtension("json")
        let bytes = Data("malformed fixture".utf8)
        try bytes.write(to: url)
        let model = PaperAssistantModel()
        model.load(root: root, record: record)
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.paper)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}

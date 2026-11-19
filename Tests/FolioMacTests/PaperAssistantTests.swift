import XCTest
import FolioCore
@testable import FolioMac

final class PaperAssistantTests: XCTestCase {
    @MainActor
    func testStoredReadingPageKeepsQuestionAndPassagePresentation() {
        let plain = AskPanel.split("[Reading page 4 of 10]\nWhat happens here?")
        XCTAssertEqual(plain.question, "What happens here?")
        XCTAssertNil(plain.passage)
        let stored = "Selected passage (p. 4):\nExact source.\n\nExplain it."
        let legacy = AskPanel.split(stored)
        let current = AskPanel.split("[Reading page 4 of 10]\n" + stored)
        XCTAssertEqual(current.question, legacy.question)
        XCTAssertEqual(current.passage, legacy.passage)
        XCTAssertEqual(current.question, "Explain it.")
        XCTAssertTrue(current.passage?.contains("Exact source.") == true)
    }

    @MainActor
    func testResumeChatSelectsExactPaperAndThreadWithoutSending() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioResumeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let first = try XCTUnwrap(workspace.activePaper)
        let model = PaperAssistantModel()
        model.load(root: root, record: first)
        let fingerprint = try XCTUnwrap(model.paper?.fingerprint)
        var history = AssistantThreads(paperID: first.id, fingerprint: fingerprint)
        history.append(question: "First question", answer: "First answer", titleSource: "First chat")
        let targetID = try XCTUnwrap(history.activeID)
        history.newThread()
        history.append(question: "Second question", answer: "Second answer", titleSource: "Second chat")
        let repository = AssistantThreadRepository(root: root, paperID: first.id, fingerprint: fingerprint)
        try repository.save(history)
        let bytes = try Data(contentsOf: repository.url)
        workspace.sample()
        workspace.showInsights(for: first)
        workspace.resumeChat(targetID, for: first)
        XCTAssertTrue(workspace.reading)
        XCTAssertEqual(workspace.activeID, first.id)
        XCTAssertEqual(workspace.panel, .ask)
        XCTAssertTrue(workspace.inspector)
        let assistant = try XCTUnwrap(workspace.activeAIStore?.assistant)
        XCTAssertEqual(assistant.threads?.activeID, targetID)
        XCTAssertEqual(assistant.activeTurns.map(\.content), ["First question", "First answer"])
        XCTAssertFalse(assistant.busy)
        XCTAssertNil(assistant.pendingQuestion)
        XCTAssertEqual(try Data(contentsOf: repository.url), bytes)
    }

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
    @MainActor
    func testFailedChatDeletionKeepsErrorAndCanRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let record = try XCTUnwrap(workspace.activePaper)
        let model = PaperAssistantModel()
        model.load(root: root, record: record)
        let repository = AssistantThreadRepository(root: root, paperID: record.id, fingerprint: try XCTUnwrap(model.paper?.fingerprint))
        var history = try XCTUnwrap(model.threads)
        history.append(question: "Question", answer: "Answer", titleSource: "Fixture")
        try repository.save(history)
        model.threads = history
        let id = try XCTUnwrap(history.activeID)
        let bytes = try Data(contentsOf: repository.url)
        let held = repository.url.appendingPathExtension("held")
        try FileManager.default.moveItem(at: repository.url, to: held)
        try FileManager.default.createDirectory(at: repository.url, withIntermediateDirectories: false)
        model.delete(id)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.threads, history)
        XCTAssertEqual(try Data(contentsOf: held), bytes)
        try FileManager.default.removeItem(at: repository.url)
        try FileManager.default.moveItem(at: held, to: repository.url)
        model.delete(id)
        XCTAssertNil(model.error)
        XCTAssertTrue(try repository.load(legacyTurns: []).threads.isEmpty)
    }

    @MainActor
    func testRemovedPaperCannotSaveDelayedAICompletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let record = try XCTUnwrap(workspace.activePaper)
        let started = expectation(description: "Fake provider started")
        let process = DelayedLogicProcess(started: { started.fulfill() })
        let service = AssistantService(client: AssistantClient(environment: [
            "FOLIO_CODEX_CLI": "/usr/bin/true", "FOLIO_PAPER_TOOLS_CLI": "/usr/bin/true"
        ], process: process))
        let assistant = PaperAssistantModel(service: service)
        assistant.load(root: root, record: record)
        workspace.aiStore = PaperAIStore(paperID: record.id, assistant: assistant)
        assistant.ask("Explain the claim", provider: .codex, page: 1, selection: nil, simplified: false)
        await fulfillment(of: [started], timeout: 5)
        workspace.removePaper(record)
        await process.finish()
        // Wait for the model's cancellation path, not for elapsed wall-clock time.
        for _ in 0..<1000 where assistant.busy { await Task.yield() }
        XCTAssertFalse(assistant.busy)
        XCTAssertNil(workspace.aiStore)
        XCTAssertTrue(assistant.activeTurns.isEmpty)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Assistant").path)) ?? []
        XCTAssertTrue(files.isEmpty)
    }

}


private actor DelayedLogicProcess: AssistantProcessRunning {
    let started: @Sendable () -> Void
    var continuation: CheckedContinuation<Data, Never>?
    init(started: @escaping @Sendable () -> Void) { self.started = started }
    func run(executable: URL, arguments: [String], environment: [String: String], directory: URL, input: Data, allowResearch: Bool) async throws -> Data {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started()
        }
    }
    func finish() {
        let response = """
        {"type":"item.completed","item":{"id":"answer","type":"agent_message","text":"Delayed fixture answer."}}
        {"type":"turn.completed"}
        """
        continuation?.resume(returning: Data(response.utf8)); continuation = nil
    }
}

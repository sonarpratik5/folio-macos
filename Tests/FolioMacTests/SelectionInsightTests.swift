import XCTest
import PDFKit
import FolioCore
@testable import FolioMac

final class SelectionInsightTests: XCTestCase {
    @MainActor
    func testSelectionExplanationIgnoresUnreadableOrStaleHistoryAndPreservesFiles() async throws {
        for fixture in ["snapshot", "threads", "stale"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioInsightHistory-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let workspace = Workspace(libraryRoot: root)
            workspace.sample()
            let record = try XCTUnwrap(workspace.activePaper)
            let paper = try PaperAssistantModel.readPaper(root: root, record: record)
            let snapshotURL = AssistantRepository(root: root, paperID: record.id, paper: paper).url
            let threadsURL = AssistantThreadRepository(root: root, paperID: record.id, fingerprint: paper.fingerprint).url
            try FileManager.default.createDirectory(at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var snapshot = AssistantSnapshot(paperID: record.id, paper: paper)
            if fixture == "stale" {
                snapshot = AssistantSnapshot(paperID: record.id, paper: try AssistantPaper(title: record.title,
                    pages: Array(repeating: "Earlier PDF text", count: record.pageCount)))
            }
            let snapshotBytes = fixture == "snapshot" ? Data("unreadable snapshot".utf8) : try JSONEncoder().encode(snapshot)
            let threadsBytes = fixture == "threads" ? Data("unreadable threads".utf8) : try JSONEncoder().encode(
                AssistantThreads(paperID: record.id, fingerprint: paper.fingerprint))
            try snapshotBytes.write(to: snapshotURL)
            try threadsBytes.write(to: threadsURL)
            // Confirm this fixture blocks normal history loading before exercising the popup's path.
            let assistant = PaperAssistantModel()
            assistant.load(root: root, record: record)
            XCTAssertNotNil(assistant.error, fixture)
            XCTAssertNil(assistant.paper, fixture)

            let transport = InsightTransport()
            let model = SelectionInsightModel(service: AssistantService(client: AssistantClient(
                environment: ["ANTHROPIC_API_KEY": "synthetic-key"], transport: transport)))
            await model.explain(SelectionInsightRequest(text: "Research begins", page: 1), root: root,
                                record: record, provider: .claude, refresh: true)
            XCTAssertFalse(model.answer.isEmpty, fixture)
            XCTAssertNil(model.error, fixture)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1, fixture)
            XCTAssertEqual(try Data(contentsOf: snapshotURL), snapshotBytes, fixture)
            XCTAssertEqual(try Data(contentsOf: threadsURL), threadsBytes, fixture)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: snapshotURL.deletingLastPathComponent().path)),
                           Set([snapshotURL.lastPathComponent, threadsURL.lastPathComponent]), fixture)
        }
    }

    @MainActor
    func testUnreadableManagedPDFDoesNotSendSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioInsightMissingPDF-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let record = try XCTUnwrap(workspace.activePaper)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Documents").appendingPathComponent(record.id.uuidString).appendingPathExtension("pdf"))
        let transport = InsightTransport()
        let model = SelectionInsightModel(service: AssistantService(client: AssistantClient(
            environment: ["ANTHROPIC_API_KEY": "synthetic-key"], transport: transport)))
        await model.explain(SelectionInsightRequest(text: "Research begins", page: 1), root: root, record: record, provider: .claude)
        XCTAssertEqual(model.error, "This managed PDF could not be read.")
        XCTAssertTrue(model.answer.isEmpty)
        XCTAssertFalse(model.busy)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testOnlyExplicitInsightsModeCreatesOneRequestPerSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioSelectionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let document = try XCTUnwrap(workspace.document)
        let view = ToolPDFView()
        view.workspace = workspace; view.document = document
        workspace.pdfView = view
        let selection = try XCTUnwrap(document.findString("Research begins", withOptions: []).first)
        view.setCurrentSelection(selection, animate: false)
        workspace.explainFinishedSelection()
        XCTAssertNil(workspace.selectionInsight)
        workspace.inspector = false
        let originalPanel = workspace.panel
        workspace.chooseInsightsMode()
        XCTAssertTrue(workspace.insightsMode)
        XCTAssertNil(workspace.selectionInsight) // Enabling alone never sends.
        workspace.explainFinishedSelection()
        let request = try XCTUnwrap(workspace.selectionInsight)
        XCTAssertEqual(request.text, "Research begins")
        XCTAssertEqual(request.page, 1)
        XCTAssertEqual(workspace.panel, originalPanel)
        XCTAssertFalse(workspace.inspector)
        XCTAssertFalse(request.bounds.isEmpty)
        workspace.explainFinishedSelection()
        XCTAssertEqual(workspace.selectionInsight?.id, request.id)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        view.keyDown(with: escape)
        XCTAssertNil(workspace.selectionInsight)
        XCTAssertTrue(workspace.insightsMode)
        workspace.explainFinishedSelection()
        XCTAssertNotNil(workspace.selectionInsight)
        workspace.chooseTool(.highlight)
        XCTAssertFalse(workspace.insightsMode)
        XCTAssertNil(workspace.selectionInsight)
        workspace.chooseInsightsMode()
        workspace.present(.assistant)
        XCTAssertFalse(workspace.insightsMode)
        XCTAssertNil(workspace.selectionInsight)
        workspace.chooseInsightsMode()
        workspace.navigate(to: .insights)
        XCTAssertFalse(workspace.insightsMode)
        XCTAssertNil(workspace.selectionInsight)
    }

    @MainActor
    func testPopupUsesSelectionGeometryAndDismissalClearsRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioPopupTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let document = try XCTUnwrap(workspace.document)
        let view = ToolPDFView(frame: CGRect(x: 0, y: 0, width: 800, height: 700))
        view.workspace = workspace; view.document = document; workspace.pdfView = view
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let selection = try XCTUnwrap(document.findString("Research begins", withOptions: []).first)
        view.setCurrentSelection(selection, animate: false)
        workspace.chooseInsightsMode(); workspace.explainFinishedSelection()
        // Remove the paper record so rendering cannot issue a provider request.
        let popupWorkspace = Workspace(libraryRoot: root.appendingPathComponent("empty"))
        popupWorkspace.reading = true; popupWorkspace.insightsMode = true
        popupWorkspace.selectionInsight = workspace.selectionInsight
        let coordinator = PDFCanvas.Coordinator(workspace: popupWorkspace)
        coordinator.updateInsight(in: view)
        let popup = try XCTUnwrap(coordinator.insightPopover)
        XCTAssertTrue(popup.isShown)
        XCTAssertEqual(popup.behavior, .transient)
        popup.performClose(nil)
        await Task.yield()
        XCTAssertNil(popupWorkspace.selectionInsight)
        XCTAssertNil(coordinator.insightPopover)
        XCTAssertTrue(popupWorkspace.insightsMode)
    }

    @MainActor
    func testExplanationUsesSelectedPassageAndPageWithoutWritingHistory() async throws {
        let transport = InsightTransport()
        let model = SelectionInsightModel(service: AssistantService(client: AssistantClient(
            environment: ["ANTHROPIC_API_KEY": "synthetic-key"], transport: transport)))
        let paper = try AssistantPaper(title: "Fixture", pages: ["First page context. \(UUID().uuidString)", "The selected term is evidence."])
        await model.explain(SelectionInsightRequest(text: "evidence", page: 2), paper: paper, provider: .claude)
        XCTAssertEqual(model.answer, "Evidence supports the claim (p. 2).")
        XCTAssertNil(model.error)
        XCTAssertFalse(model.busy)
        // A second host for the same passage reuses the session result.
        let reopened = SelectionInsightModel(service: AssistantService(client: AssistantClient(
            environment: ["ANTHROPIC_API_KEY": "synthetic-key"], transport: transport)))
        await reopened.explain(SelectionInsightRequest(text: "evidence", page: 2), paper: paper, provider: .claude)
        XCTAssertEqual(reopened.answer, model.answer)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let body = try XCTUnwrap(requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(content.contains("Reading page 2"))
        XCTAssertTrue(content.contains("evidence"))
        XCTAssertTrue(content.contains("80 words"))
        XCTAssertTrue(content.contains("surrounding_passage"))
        XCTAssertTrue(content.contains("The selected term is evidence."))
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }), Set(["search_paper", "read_paper_page", "web_search"]))
    }
}

private actor InsightTransport: AssistantTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(#"{"content":[{"type":"text","text":"Evidence supports the claim (p. 2)."}],"stop_reason":"end_turn"}"#.utf8), 200)
    }
}

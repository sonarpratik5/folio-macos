import XCTest
@testable import FolioCore

final class AssistantThreadsTests: XCTestCase {
    private func paper() throws -> AssistantPaper {
        try AssistantPaper(title: "Fixture", pages: ["Sleep improved memory in the study group. We find consistent gains across all measured tasks and sessions.", "Results show a clear effect (p. 2)."])
    }

    func testThreadLifecycleAndPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("threads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(); let paper = try paper()
        let repo = AssistantThreadRepository(root: root, paperID: id, fingerprint: paper.fingerprint)
        var threads = try repo.load(legacyTurns: [])
        XCTAssertTrue(threads.threads.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        threads.append(question: "q1", answer: "a1", titleSource: "What is the main claim of this paper?")
        let first = try XCTUnwrap(threads.active)
        XCTAssertEqual(first.title, "What is the main claim of this paper?")
        threads.newThread(); threads.append(question: "q2", answer: "a2", titleSource: "Second")
        XCTAssertEqual(threads.threads.count, 2)
        threads.rename(first.id, to: "  Renamed   chat ")
        try repo.save(threads)
        var loaded = try repo.load(legacyTurns: [])
        XCTAssertEqual(loaded.threads.first { $0.id == first.id }?.title, "Renamed chat")
        loaded.delete(try XCTUnwrap(loaded.activeID))
        XCTAssertEqual(loaded.threads.count, 1)
        XCTAssertEqual(loaded.activeID, loaded.threads.first?.id)
        try repo.save(loaded)
        // Reusing an empty chat avoids blank pile-ups.
        loaded.newThread(); let count = loaded.threads.count; loaded.newThread()
        XCTAssertEqual(loaded.threads.count, count)
    }

    func testLegacyTurnsMigrateAndMalformedFileIsPreserved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("threads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(); let paper = try paper()
        let repo = AssistantThreadRepository(root: root, paperID: id, fingerprint: paper.fingerprint)
        let turns = [AssistantTurn(role: .user, content: "Hello there"), AssistantTurn(role: .assistant, content: "Hi")]
        XCTAssertEqual(try repo.load(legacyTurns: turns).threads.first?.turns, turns)
        try FileManager.default.createDirectory(at: repo.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data("not json".utf8); try bytes.write(to: repo.url)
        XCTAssertThrowsError(try repo.load(legacyTurns: []))
        XCTAssertEqual(try Data(contentsOf: repo.url), bytes)
    }

    func testRichTextBlocksMathAndCitations() {
        let text = "# Title\nSee (p. 4) and $x_i^2 + \\alpha$.\n\n- one\n- two\n\n```swift\nlet a = 1\n```\n$$\n\\frac{a}{b} = \\sqrt{c}\n$$"
        let blocks = AssistantRichText.blocks(text)
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0], .heading(1, "Title"))
        XCTAssertEqual(blocks[2], .bullets(["one", "two"]))
        XCTAssertEqual(blocks[3], .code(language: "swift", text: "let a = 1"))
        XCTAssertEqual(blocks[4], .math("\\frac{a}{b} = \\sqrt{c}"))
        guard case .paragraph(let paragraph) = blocks[1] else { return XCTFail() }
        let inline = AssistantRichText.inlineMarkdown(paragraph, pageCount: 10)
        XCTAssertTrue(inline.contains("[p. 4](folio-page://4)"))
        XCTAssertTrue(inline.contains("xᵢ²") || inline.contains("x\\_i²") || inline.contains("x"))
        XCTAssertTrue(inline.contains("α"))
        XCTAssertEqual(AssistantRichText.latex("\\frac{a}{b} = \\sqrt{c}"), "a⁄b = √(c)")
        XCTAssertEqual(AssistantRichText.page(from: URL(string: "folio-page://7")!), 7)
        XCTAssertFalse(AssistantRichText.inlineMarkdown("see p. 99", pageCount: 10).contains("folio-page"))
        XCTAssertEqual(AssistantRichText.inlineMarkdown("costs $5 and $6 total"), "costs $5 and $6 total")
    }

    func testStreamingClaudeEmitsProgressiveTextAndRunsToolLoop() async throws {
        let first = """
        event: message_start
        data: {"type":"message_start","message":{"content":[]}}
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"read_paper_page","input":{}}}
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"page\\":"}}
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"2}"}}
        data: {"type":"content_block_stop","index":0}
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}
        """
        let second = """
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Streamed "}}
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"answer (p. 2)."}}
        data: {"type":"content_block_stop","index":0}
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}
        """
        let transport = StreamFake(bodies: [first, second])
        let client = AssistantClient(environment: ["ANTHROPIC_API_KEY": "fixture-key"], transport: transport)
        let chunks = Chunks()
        let answer = try await AssistantService(client: client).answer(question: "What?", paper: paper(), history: [], provider: .claude, page: 1, onText: { chunks.add($0) })
        XCTAssertEqual(answer, "Streamed answer (p. 2).")
        XCTAssertEqual(chunks.all, ["Streamed ", "answer (p. 2)."])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(String(decoding: requests[0].httpBody!, as: UTF8.self).contains("\"stream\":true"))
        XCTAssertTrue(String(decoding: requests[1].httpBody!, as: UTF8.self).contains("tool_result"))
    }

    func testStreamErrorEventSurfacesWithoutFallback() async throws {
        let transport = StreamFake(bodies: [#"data: {"type":"error","error":{"type":"overloaded_error","message":"x"}}"#])
        let client = AssistantClient(environment: ["ANTHROPIC_API_KEY": "fixture-key"], transport: transport)
        do { _ = try await AssistantService(client: client).answer(question: "What?", paper: paper(), history: [], provider: .claude, page: 1, onText: { _ in }); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("overloaded")) }
    }

    func testAbstractStopsBeforeNumberedHeading() {
        let abstract = "Research begins with a question. Read the abstract, identify the method, and check what evidence supports each claim. Keep your own notes beside the source."
        let insights = InsightAnalysis.analyze(pages: ["Title\nAbstract\n" + abstract + "\n1. Read with a question\nThis is body text that must stay out of the abstract.", "Another page of body text."])
        XCTAssertEqual(insights.abstract, abstract)
        XCTAssertFalse(insights.abstract.contains("body text"))
    }

    func testLocalInsightsFindKeySentencesWithPages() {
        let pages = [
            "Abstract Sleep improved memory consolidation in adults across several controlled sessions of testing. We find consistent gains in recall. Introduction Sleep matters for memory and learning in many animals and humans alike.",
            "We show that sleep deprivation reduces memory consolidation in a controlled experiment with adults. Results show that memory consolidation improved after sleep in every group tested."
        ]
        let insights = InsightAnalysis.analyze(pages: pages)
        XCTAssertFalse(insights.keySentences.isEmpty)
        XCTAssertTrue(insights.keySentences.allSatisfy { (1...2).contains($0.page) })
        XCTAssertTrue(insights.keywords.contains { $0.term.contains("memory") || $0.term.contains("sleep") })
        XCTAssertTrue(insights.abstract.hasPrefix("Sleep improved"))
    }
}

private final class Chunks: @unchecked Sendable {
    private let lock = NSLock(); private var items: [String] = []
    func add(_ text: String) { lock.lock(); items.append(text); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
private actor StreamFake: AssistantTransport {
    var bodies: [String]
    var requests: [URLRequest] = []
    init(bodies: [String]) { self.bodies = bodies }
    func send(_ request: URLRequest) async throws -> (Data, Int) { throw URLError(.badServerResponse) }
    func stream(_ request: URLRequest) async throws -> (Int, AsyncThrowingStream<String, Error>) {
        requests.append(request)
        let lines = bodies.removeFirst().split(separator: "\n").map(String.init)
        return (200, AsyncThrowingStream { continuation in lines.forEach { continuation.yield($0) }; continuation.finish() })
    }
}

import XCTest
@testable import FolioCore

final class AssistantTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioAssistantTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func paper() throws -> AssistantPaper {
        try AssistantPaper(title: "Disposable fixture", pages: [
            "The problem is that tiny widgets lose energy. " + String(repeating: "A widget is a test object. ", count: 60),
            "Our approach uses a soft shell around each widget. " + String(repeating: "We test widgets with a fixed apparatus. ", count: 60),
            "The experiment reports lower energy loss in ten measured widgets. " + String(repeating: "The evaluation has a small sample. ", count: 60)
        ])
    }
    private func overviewJSON(ref: Int = 0) -> String {
        """
        {"problem":{"available":true,"label":"Widgets lose stored energy","explanation":"The paper studies energy loss in widgets.","sentence_ids":[\(ref)]},"approach":{"available":false,"label":"","explanation":"","sentence_ids":[]},"finding":{"available":false,"label":"","explanation":"","sentence_ids":[]}}
        """
    }
    func testDistributedContextIsDeterministicAndBounded() throws {
        let pages = (1...250).map { page in String(repeating: "Page \(page) says this evidence is limited. ", count: 400) }
        let first = try AssistantPaper(title: "Long fixture", pages: pages)
        let second = try AssistantPaper(title: "Long fixture", pages: pages)
        XCTAssertEqual(first.passages, second.passages)
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertTrue(first.sampled)
        XCTAssertLessThanOrEqual(first.passages.count, 800)
        XCTAssertLessThanOrEqual(first.passages.reduce(0) { $0 + AssistantPaper.quoted($1.text).utf8.count + 80 }, 40_000)
        XCTAssertTrue(first.passages.contains { $0.page == 250 })
        XCTAssertNoThrow(try PaperLookup(pages: first.lookupPages, truncated: first.truncatedPages))
        XCTAssertEqual(first.chatContext, second.chatContext)
        XCTAssertLessThanOrEqual(first.chatContext.count, 12_000)
        XCTAssertTrue(first.chatContext.contains("[Page 1]"))
        XCTAssertTrue(first.chatContext.contains("[Page 250]"))
        XCTAssertTrue(first.chatContext.contains("not complete evidence"))
        XCTAssertLessThan(first.chatContext.count, first.context.count)
        let escaped = try AssistantPaper(title: "Unicode fixture", pages: Array(repeating: String(repeating: "研究\n\"evidence\" ", count: 15_000), count: 30))
        XCTAssertNoThrow(try PaperLookup(pages: escaped.lookupPages, truncated: escaped.truncatedPages))
        XCTAssertTrue(escaped.truncatedPages.contains(true))
        XCTAssertNotEqual(first.fingerprint, try AssistantPaper(title: "Long fixture", pages: pages + ["New page"]).fingerprint)
        XCTAssertNotEqual(try AssistantPaper(title: "Boundary fixture", pages: ["a\u{0000}b", "c"]).fingerprint,
                          try AssistantPaper(title: "Boundary fixture", pages: ["a", "b\u{0000}c"]).fingerprint)
    }
    func testSelectionWindowFindsDeepTextAndStaysBounded() throws {
        let source = String(repeating: "Opening background. ", count: 200) + "This method uses adaptive routing to reduce cost. " + String(repeating: "Later evidence. ", count: 200)
        let paper = try AssistantPaper(title: "Window fixture", pages: [source])
        let window = try XCTUnwrap(paper.selectionContext("adaptive\nrouting", page: 1))
        XCTAssertTrue(window.contains("This method uses adaptive routing to reduce cost."))
        XCTAssertLessThanOrEqual(window.count, 1600)
        XCTAssertFalse(window.hasPrefix("Opening background."))
        XCTAssertNil(paper.selectionContext("missing term", page: 1))
        XCTAssertNil(paper.selectionContext("adaptive routing", page: 2))
        XCTAssertNil(paper.selectionContext("", page: 1))
        XCTAssertNil(paper.selectionContext(String(repeating: "a", count: 1201), page: 1))
    }
    func testLongSelectionKeepsAdjacentEvidenceWithoutRepeatingSelection() throws {
        let selection = String(repeating: "Selected technical evidence. ", count: 80)
        let paper = try AssistantPaper(title: "Long selection", pages: ["PRECEDING definition. " + selection + " FOLLOWING limitation."])
        let window = try XCTUnwrap(paper.selectionContext(selection, page: 1))
        XCTAssertTrue(window.contains("PRECEDING definition"))
        XCTAssertTrue(window.contains("FOLLOWING limitation"))
        XCTAssertFalse(window.contains(selection))
        XCTAssertLessThan(window.count, 1300)
    }

    func testHistoryRetainsNewestCompleteExchangeAndUnicodeWithinByteBudget() {
        let longAnswer = "BEGIN " + String(repeating: "研究🙂", count: 8000) + " END (p. 7)"
        let history = [AssistantTurn(role: .assistant, content: "Orphan"),
                       AssistantTurn(role: .user, content: "Old question"), AssistantTurn(role: .assistant, content: "Old answer"),
                       AssistantTurn(role: .user, content: "Recent question"), AssistantTurn(role: .assistant, content: longAnswer)]
        let recent = AssistantService.compactHistory(history, budget: 12_000)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.first?.content, "Recent question")
        XCTAssertTrue(recent.last!.content.hasPrefix("BEGIN"))
        XCTAssertTrue(recent.last!.content.hasSuffix("END (p. 7)"))
        XCTAssertTrue(recent.last!.content.contains("omitted"))
        XCTAssertFalse(recent.last!.content.contains("�"))
        XCTAssertLessThan(recent.reduce(0) { $0 + $1.content.utf8.count + 100 }, 12_000)
        XCTAssertTrue(AssistantService.compactHistory(history, budget: 10).isEmpty)
        XCTAssertEqual(history.last?.content, longAnswer)
    }

    func testQuestionRetrievesDeepAppendixAndCurrentPageWithoutFullPDF() async throws {
        let pages = ["Opening abstract.", "Local explanation on the current page.",
                     String(repeating: "Unrelated background. ", count: 200) + "Zirconium ablation reduces energy by 17 percent."]
        let paper = try AssistantPaper(title: "Retrieval fixture", pages: pages)
        let transport = FakeTransport(responses: [(Data(#"{"content":[{"type":"text","text":"17 percent (p. 3)."}],"stop_reason":"end_turn"}"#.utf8), 200)])
        let service = AssistantService(client: AssistantClient(environment: ["ANTHROPIC_API_KEY": "fixture"], transport: transport))
        _ = try await service.answer(question: "How does zirconium ablation relate to this page?", paper: paper, history: [], provider: .claude, page: 2)
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let latest = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(latest.contains("Zirconium ablation reduces energy by 17 percent"))
        XCTAssertTrue(latest.contains("PDF page 3"))
        XCTAssertTrue(latest.contains("Local explanation on the current page"))
        XCTAssertLessThan(latest.utf8.count, 4500)
        XCTAssertNotNil(body["tools"])
    }

    func testStructuredContextIsByteBoundedForMultilingualPapers() throws {
        let paper = try AssistantPaper(title: "Unicode", pages: (1...80).map { "Page \($0) " + String(repeating: "研究🙂 results evidence ", count: 300) })
        XCTAssertLessThanOrEqual(paper.context.utf8.count, 40_000)
        XCTAssertTrue(paper.passages.contains { $0.page == 80 })
        XCTAssertTrue(paper.sampled)
    }

    func testOverviewSourcesAlwaysComeFromExtractionAndRejectInventedIDs() throws {
        let paper = try paper()
        let overview = try AssistantOverview.parse(overviewJSON(), paper: paper, provider: .codex)
        XCTAssertEqual(overview.cards.first?.sources.first, paper.passages.first)
        XCTAssertThrowsError(try AssistantOverview.parse(overviewJSON(ref: 99999), paper: paper, provider: .codex))
        XCTAssertThrowsError(try AssistantOverview.parse(overviewJSON().replacingOccurrences(of: "[0]", with: "[true]"), paper: paper, provider: .codex))
        XCTAssertThrowsError(try AssistantOverview.parse(overviewJSON().replacingOccurrences(of: "true", with: "1"), paper: paper, provider: .codex))
        XCTAssertThrowsError(try AssistantOverview.parse(overviewJSON().replacingOccurrences(of: "[0]", with: "[1e99]"), paper: paper, provider: .codex))
        XCTAssertThrowsError(try AssistantOverview.parse(overviewJSON().replacingOccurrences(of: "Widgets lose stored energy", with: String(repeating: "long ", count: 10)), paper: paper, provider: .codex))
    }
    func testPersistenceRoundTripAndCorruptionFailsClosed() throws {
        let root = try directory(), paper = try paper(), id = UUID()
        let repository = AssistantRepository(root: root, paperID: id, paper: paper)
        var snapshot = try repository.load()
        snapshot.turns = [AssistantTurn(role: .user, content: "Question"), AssistantTurn(role: .assistant, content: "Answer (p. 1)")]
        snapshot.overview = try AssistantOverview.parse(overviewJSON(), paper: paper, provider: .codex)
        try repository.save(snapshot)
        XCTAssertEqual(try repository.load().turns, snapshot.turns)
        XCTAssertEqual(try repository.load().overview, snapshot.overview)
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(snapshot))
        XCTAssertEqual(try Data(contentsOf: repository.url), corrupt)
    }
    func testChangedPDFDoesNotReuseOrOverwriteConversation() throws {
        let root = try directory(), id = UUID(), original = try paper()
        let old = AssistantRepository(root: root, paperID: id, paper: original)
        try old.save(AssistantSnapshot(paperID: id, paper: original))
        let bytes = try Data(contentsOf: old.url)
        let changed = try AssistantPaper(title: original.title, pages: ["Changed first page", "Changed second page", "Changed third page"])
        let next = AssistantRepository(root: root, paperID: id, paper: changed)
        XCTAssertThrowsError(try next.load())
        XCTAssertThrowsError(try next.save(AssistantSnapshot(paperID: id, paper: changed)))
        XCTAssertEqual(try Data(contentsOf: old.url), bytes)
    }
    func testPaperLookupBoundsAndContinuation() throws {
        let paper = try AssistantPaper(title: "Fixture", pages: [String(repeating: "fixture ", count: 3000), "A needle occurs here."])
        let page = AssistantClient.paperLookup(name: "read_paper_page", input: ["page": 1], paper: paper)
        XCTAssertEqual((page["text"] as? String)?.count, 12_000)
        XCTAssertEqual(page["nextStart"] as? Int, 12_000)
        let search = AssistantClient.paperLookup(name: "search_paper", input: ["query": "needle"], paper: paper)
        XCTAssertEqual((search["results"] as? [[String: Any]])?.first?["page"] as? Int, 2)
        XCTAssertNotNil(AssistantClient.paperLookup(name: "read_paper_page", input: ["page": -1], paper: paper)["error"])
        XCTAssertNotNil(AssistantClient.paperLookup(name: "shell", input: [:], paper: paper)["error"])
    }
    func testCodexRequestIsIsolatedRestrictedAndCredentialFree() async throws {
        let fake = RecordingProcess(output: """
        {"type":"item.completed","item":{"id":"answer","type":"agent_message","text":"A fixture answer (p. 1)."}}
        {"type":"turn.completed"}
        """)
        let client = AssistantClient(environment: ["FOLIO_CODEX_CLI": "/usr/bin/true", "ANTHROPIC_API_KEY": "never-pass-to-child", "OPENAI_API_KEY": "also-never", "CODEX_THREAD_ID": "unrelated-thread"], process: fake)
        let result = try await client.ask(AssistantRequest(system: "Application instructions", messages: [AssistantTurn(role: .user, content: "A test question")], paper: paper()), provider: .codex)
        XCTAssertEqual(result, "A fixture answer (p. 1).")
        XCTAssertEqual(fake.instructions, "Application instructions")
        XCTAssertNil(fake.environment["ANTHROPIC_API_KEY"])
        XCTAssertNil(fake.environment["OPENAI_API_KEY"])
        XCTAssertNil(fake.environment["CODEX_THREAD_ID"])
        XCTAssertTrue(fake.arguments.contains("--ignore-user-config"))
        XCTAssertTrue(fake.arguments.contains("--ignore-rules"))
        XCTAssertTrue(fake.arguments.contains("--ephemeral"))
        XCTAssertTrue(fake.arguments.contains("features.shell_tool=false"))
        XCTAssertTrue(fake.arguments.contains("project_doc_max_bytes=0"))
        XCTAssertTrue(fake.arguments.contains("web_search=\"disabled\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(fake.directory).path))
    }
    func testClaudeToolRoundTripAndNoSilentFallback() async throws {
        let transport = FakeTransport(responses: [
            (Data(#"{"content":[{"type":"tool_use","id":"lookup","name":"read_paper_page","input":{"page":2}}],"stop_reason":"tool_use"}"#.utf8), 200),
            (Data(#"{"content":[{"type":"text","text":"The approach uses a soft shell (p. 2)."}],"stop_reason":"end_turn"}"#.utf8), 200)
        ])
        let client = AssistantClient(environment: ["ANTHROPIC_API_KEY": "fixture-key"], transport: transport)
        let result = try await AssistantService(client: client).answer(question: "What is the approach?", paper: paper(), history: [], provider: .claude, page: 1)
        XCTAssertTrue(result.contains("p. 2"))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let second = try XCTUnwrap(String(data: requests[1].httpBody!, encoding: .utf8))
        XCTAssertTrue(second.contains("soft shell"))
        XCTAssertTrue(second.contains("tool_result"))
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "x-api-key"), "fixture-key")
        let failing = FakeTransport(responses: [(Data(#"{"error":{"message":"secret provider diagnostics"}}"#.utf8), 401)])
        do {
            _ = try await AssistantClient(environment: ["ANTHROPIC_API_KEY": "fixture-key"], transport: failing).ask(AssistantRequest(system: "Test", messages: [], paper: paper()), provider: .claude)
            XCTFail("Expected failure")
        } catch { XCTAssertFalse(error.localizedDescription.contains("secret provider diagnostics")); XCTAssertTrue(error.localizedDescription.contains("rejected")) }
    }
    func testClaudeKeyComesFromEnvironmentThenStoredKey() async throws {
        let ok = { FakeTransport(responses: [(Data(#"{"content":[{"type":"text","text":"Fine."}],"stop_reason":"end_turn"}"#.utf8), 200)]) }
        let request = AssistantRequest(system: "Test", messages: [AssistantTurn(role: .user, content: "Hi")], paper: try paper())
        let stored = ok()
        _ = try await AssistantClient(environment: [:], transport: stored, storedKey: { "keychain-key" }).ask(request, provider: .claude)
        let storedRequests = await stored.requests
        XCTAssertEqual(storedRequests.first?.value(forHTTPHeaderField: "x-api-key"), "keychain-key")
        let env = ok()
        _ = try await AssistantClient(environment: ["ANTHROPIC_API_KEY": "env-key"], transport: env, storedKey: { "keychain-key" }).ask(request, provider: .claude)
        let envRequests = await env.requests
        XCTAssertEqual(envRequests.first?.value(forHTTPHeaderField: "x-api-key"), "env-key")
        let blocked = FakeTransport(responses: [])
        do {
            _ = try await AssistantClient(environment: [:], transport: blocked, storedKey: { nil }).ask(request, provider: .claude)
            XCTFail("Expected missing-key failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("ANTHROPIC_API_KEY"))
            XCTAssertTrue(error.localizedDescription.contains("will not open a Keychain password prompt"))
        }
        let blockedRequests = await blocked.requests
        XCTAssertTrue(blockedRequests.isEmpty)
    }
    func testRunnerRejectsForbiddenToolsAndCancelsProcess() async throws {
        let root = try directory()
        let script = #"printf '%s\n' '{"type":"item.started","item":{"id":"bad","type":"command_execution"}}'; exec sleep 20"#
        do {
            _ = try await AssistantProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], environment: ["PATH": "/bin:/usr/bin"], directory: root, input: Data(), allowResearch: false)
            XCTFail("Expected forbidden-tool rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("permissions")) }
        let task = Task {
            try await AssistantProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "trap '' TERM; exec /bin/sleep 20"], environment: [:], directory: root, input: Data(), allowResearch: false)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let cancelledAt = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 10)
    }

    func testRunnerDrainsCompletedOutputBeforeReturning() async throws {
        let expected = "{\"type\":\"turn.completed\"}\n"
        let data = try await AssistantProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", expected], environment: [:], directory: directory(), input: Data(), allowResearch: false)
        XCTAssertEqual(String(data: data, encoding: .utf8), expected)
    }
}

private final class RecordingProcess: AssistantProcessRunning {
    let output: String
    var arguments: [String] = [], environment: [String: String] = [:]
    var directory: URL?, instructions: String?
    init(output: String) { self.output = output }
    func run(executable: URL, arguments: [String], environment: [String: String], directory: URL, input: Data, allowResearch: Bool) async throws -> Data {
        self.arguments = arguments; self.environment = environment; self.directory = directory
        instructions = try String(contentsOf: directory.appendingPathComponent("system.txt"), encoding: .utf8)
        return Data(output.utf8)
    }
}
private actor FakeTransport: AssistantTransport {
    var responses: [(Data, Int)]
    var requests: [URLRequest] = []
    init(responses: [(Data, Int)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); guard !responses.isEmpty else { throw URLError(.badServerResponse) }; return responses.removeFirst() }
}

final class CodexFailureTests: XCTestCase {
    private func lines(_ events: String...) -> Data { Data(events.joined(separator: "\n").utf8) }
    func testUsageLimitOnStdoutKeepsResetTime() {
        let out = lines(#"{"type":"turn.started"}"#, #"{"type":"error","message":"You’ve hit your usage limit. Upgrade to Pro (https://x) or try again at 9:13 PM."}"#)
        let message = CodexFailure.message(stdout: out, stderr: Data())
        XCTAssertTrue(message.contains("usage limit"), message)
        XCTAssertTrue(message.contains("Try again at 9:13 PM."), message)
    }
    func testSignInAndGenericFailures() {
        XCTAssertTrue(CodexFailure.message(stdout: Data(), stderr: Data("Error: not logged in".utf8)).contains("not signed in"))
        let model = CodexFailure.message(stdout: lines(#"{"type":"turn.failed","error":{"message":"model gpt-x is not available"}}"#), stderr: Data())
        XCTAssertEqual(model, "Codex failed: model gpt-x is not available")
        XCTAssertTrue(CodexFailure.message(stdout: Data(), stderr: Data()).hasPrefix("Codex failed. Check"))
    }
}

final class ClaudeDotEnvTests: XCTestCase {
    func testParsesDotEnvVariants() {
        XCTAssertEqual(ClaudeKeyStore.key(fromDotEnv: "OTHER=1\nANTHROPIC_API_KEY=sk-ant-abc\n"), "sk-ant-abc")
        XCTAssertEqual(ClaudeKeyStore.key(fromDotEnv: "export ANTHROPIC_API_KEY=\"sk-ant-q\" # note"), "sk-ant-q")
        XCTAssertEqual(ClaudeKeyStore.key(fromDotEnv: "ANTHROPIC_API_KEY = 'sk-ant-s'"), "sk-ant-s")
        XCTAssertEqual(ClaudeKeyStore.key(fromDotEnv: "ANTHROPIC_API_KEY=sk-ant-c # comment"), "sk-ant-c")
        XCTAssertNil(ClaudeKeyStore.key(fromDotEnv: "# ANTHROPIC_API_KEY=sk-ant-x\nANTHROPIC_API_KEY_OLD=y\nANTHROPIC_API_KEY=paste-here"))
    }
}

import XCTest
@testable import FolioCore

final class NativeReviewTests: XCTestCase {
    private let forumID = "Forum_123"
    private let title = "A tiny widget energy experiment"
    private func rawForum() -> [[String: Any]] {
        [
            ["id": forumID, "forum": forumID, "content": ["title": ["value": title], "venue": ["value": "ICLR 2026"]]],
            ["id": "reviewA1", "forum": forumID, "invitations": ["ICLR/Submission1/Official_Review"], "signatures": ["ICLR/Reviewer_a12"], "content": ["weaknesses": ["value": "The evaluation omits a strong baseline."], "rating": ["value": "5: Borderline"], "summary": ["value": "The paper studies tiny widgets."]]],
            ["id": "response1", "forum": forumID, "invitation": "ICLR/Submission1/Author_Response", "replyto": "reviewA1", "signatures": ["ICLR/Authors"], "content": ["rebuttal": "We added the baseline in a revised evaluation."]],
            ["id": "meta123", "forum": forumID, "invitation": "ICLR/Submission1/Meta_Review", "signatures": ["ICLR/Area_Chair"], "content": ["metareview": "The missing baseline remains an important concern."]],
            ["id": "decision1", "forum": forumID, "invitation": "ICLR/Submission1/Decision", "content": ["decision": ["value": "Accept"]]]
        ]
    }
    private func paper() throws -> AssistantPaper { try AssistantPaper(title: title, pages: ["Our method stores energy in tiny widgets.", "The experiment compares ten widgets with a simple baseline.", "The evaluation has a small sample."]) }
    private func analysisJSON() throws -> String {
        let object: [String: Any] = ["summary": "Reviewers question the baseline used in evaluation.", "summary_note_ids": ["reviewA1", "meta123"], "concerns": [[
            "title": "Missing strong evaluation baseline", "summary": "The reviewer questions whether the comparison supports the main claim.", "type": "experiments", "severity": "major", "raised_by": ["Reviewer a12"],
            "quotes": [["note_id": "reviewA1", "text": "The evaluation omits a strong baseline."]], "sentence_ids": [1], "missing": true,
            "author_response": "partially_addressed", "response_summary": "The authors report adding a baseline.", "response_note_ids": ["response1"], "in_meta_review": true
        ]]]
        return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    private func response(notes: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: ["notes": notes]) }
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioReviewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testForumParsingSourceAllowlistAndCandidateRanking() {
        XCTAssertEqual(NativeReviewsClient.forumID("https://openreview.net/forum?id=Forum_123"), forumID)
        XCTAssertEqual(NativeReviewsClient.forumID(forumID), forumID)
        XCTAssertNil(NativeReviewsClient.forumID("https://evil.example/forum?id=Forum_123"))
        XCTAssertNil(NativeReviewsClient.forumID("http://openreview.net/forum?id=Forum_123"))
        XCTAssertFalse(NativeReviewsClient.allowed(URL(string: "https://api.openreview.net.evil.example/notes")))
        XCTAssertFalse(NativeReviewsClient.allowed(URL(string: "https://key@api.openreview.net/notes")))
        XCTAssertTrue(NativeReviewsClient.allowed(URL(string: "https://api2.openreview.net/notes")))
        let ranked = NativeReviewsClient.rank(title: title, candidates: [
            ReviewCandidate(id: "Venue123", title: title, venue: "ICLR"), ReviewCandidate(id: "Import12", title: title, venue: "CoRR"),
            ReviewCandidate(id: "Venue123", title: title, venue: "ICLR"), ReviewCandidate(id: "Other123", title: "Bird migration under climate change", venue: "Ecology")
        ])
        XCTAssertEqual(ranked.map(\.id), ["Venue123", "Import12"])
    }
    func testSearchUsesBothAPIsAndOnlyTitleIdentity() async throws {
        let notes: [[String: Any]] = [["id": forumID, "forum": forumID, "content": ["title": ["value": title], "venue": ["value": "ICLR"]]]]
        let transport = ReviewFakeTransport(responses: [(try response(notes: notes), 200), (try response(notes: notes), 200)])
        let candidates = try await NativeReviewsClient(transport: transport, environment: ["OPENREVIEW_TOKEN": "fixture-token"]).search(title: title)
        XCTAssertEqual(candidates.count, 1)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Set(requests.compactMap { $0.url?.host }), Set(["api2.openreview.net", "api.openreview.net"]))
        XCTAssertTrue(requests.allSatisfy { $0.httpBody == nil && $0.timeoutInterval == 20 })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token" })
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "term" }?.value, title)
    }
    func testForumFallsBackToLegacyAndNormalizesScoresRepliesAndDecision() async throws {
        let transport = ReviewFakeTransport(responses: [(try response(notes: []), 200), (try response(notes: rawForum()), 200)])
        let forum = try await NativeReviewsClient(transport: transport, environment: [:]).forum(forumID)
        XCTAssertEqual(forum.title, title)
        XCTAssertEqual(forum.decision, "Accept")
        XCTAssertTrue(forum.hasReviews)
        XCTAssertEqual(forum.notes.first { $0.kind == "review" }?.author, "Reviewer a12")
        XCTAssertEqual(forum.notes.first { $0.kind == "review" }?.scores.first?.text, "5: Borderline")
        XCTAssertEqual(forum.notes.first { $0.kind == "rebuttal" }?.replyTo, "reviewA1")
        XCTAssertFalse(forum.context.contains("The paper studies tiny widgets."))
        XCTAssertTrue(forum.context.contains("[R:reviewA1]"))
    }
    func testConcernAnalysisRejectsFabricatedQuotesSourcesAndAuthors() throws {
        let forum = try NativeReviewsClient.normalize(rawForum(), id: forumID), paper = try paper(), json = try analysisJSON()
        let analysis = try ReviewAnalysis.parse(json, forum: forum, paper: paper, provider: .codex)
        XCTAssertEqual(analysis.concerns.first?.sources, [paper.passages[1]])
        XCTAssertEqual(analysis.concerns.first?.quotes.first?.text, "The evaluation omits a strong baseline.")
        XCTAssertThrowsError(try ReviewAnalysis.parse(json.replacingOccurrences(of: "The evaluation omits a strong baseline.", with: "A fabricated criticism."), forum: forum, paper: paper, provider: .codex))
        XCTAssertThrowsError(try ReviewAnalysis.parse(json.replacingOccurrences(of: "Reviewer a12", with: "Invented reviewer"), forum: forum, paper: paper, provider: .codex))
        XCTAssertThrowsError(try ReviewAnalysis.parse(json.replacingOccurrences(of: #""sentence_ids":[1]"#, with: #""sentence_ids":[99999]"#), forum: forum, paper: paper, provider: .codex))
        XCTAssertThrowsError(try ReviewAnalysis.parse(json.replacingOccurrences(of: #""missing":true"#, with: #""missing":1"#), forum: forum, paper: paper, provider: .codex))
    }
    func testAnalysisProviderHasNoResearchToolsAndValidatesReturnedEvidence() async throws {
        let content = try JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": try analysisJSON()]], "stop_reason": "end_turn"])
        let transport = ReviewFakeTransport(responses: [(content, 200)])
        let client = AssistantClient(environment: ["ANTHROPIC_API_KEY": "fixture-key"], transport: transport)
        let analysis = try await NativeReviewAnalysisService(client: client).analyze(forum: NativeReviewsClient.normalize(rawForum(), id: forumID), paper: paper(), provider: .claude)
        XCTAssertEqual(analysis.provider, .claude)
        let firstRequest = await transport.requests.first
        let request = try XCTUnwrap(firstRequest)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertNil(body["tools"])
        XCTAssertTrue((body["system"] as? String)?.contains("untrusted evidence") == true)
        XCTAssertTrue(String(data: request.httpBody!, encoding: .utf8)?.contains("The evaluation omits a strong baseline.") == true)
    }
    func testPersistenceAndDigestAreLocalAndCorruptionFailsClosed() throws {
        let root = try directory(), paper = try paper(), id = UUID()
        let repository = NativeReviewRepository(root: root, paperID: id, paper: paper)
        var saved = try repository.load()
        saved.forum = try NativeReviewsClient.normalize(rawForum(), id: forumID)
        saved.analysis = try ReviewAnalysis.parse(analysisJSON(), forum: saved.forum!, paper: paper, provider: .codex)
        try repository.save(saved)
        XCTAssertEqual(try repository.load().analysis, saved.analysis)
        XCTAssertTrue(saved.digest.contains("p. 2"))
        XCTAssertLessThanOrEqual(saved.digest.count, 10_000)
        var corrupt = try JSONSerialization.jsonObject(with: Data(contentsOf: repository.url)) as! [String: Any]
        corrupt["fingerprint"] = "different-paper"
        let bytes = try JSONSerialization.data(withJSONObject: corrupt)
        try bytes.write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(saved))
        XCTAssertEqual(try Data(contentsOf: repository.url), bytes)
    }
    func testNetworkErrorDoesNotExposeRawProviderDiagnostics() async throws {
        let transport = ReviewFakeTransport(responses: [(Data(#"{"message":"secret-token raw diagnostic"}"#.utf8), 401)])
        do { _ = try await NativeReviewsClient(transport: transport, environment: [:]).forum(forumID); XCTFail("Expected denied request") }
        catch { XCTAssertTrue(error.localizedDescription.contains("requires access")); XCTAssertFalse(error.localizedDescription.contains("secret-token")) }
    }
}

private actor ReviewFakeTransport: AssistantTransport {
    var responses: [(Data, Int)]
    var requests: [URLRequest] = []
    init(responses: [(Data, Int)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); guard !responses.isEmpty else { throw URLError(.badServerResponse) }; return responses.removeFirst() }
}

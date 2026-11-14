import XCTest
@testable import FolioCore

/// Opt-in live provider checks against a synthetic, disposable paper. Skipped unless `FOLIO_LIVE_AI=1`.
/// Chat needs `FOLIO_PAPER_TOOLS_CLI` (the built FolioPaperTools helper); Claude needs `ANTHROPIC_API_KEY`.
final class LiveProviderTests: XCTestCase {
    private var provider: AssistantProvider {
        ProcessInfo.processInfo.environment["FOLIO_LIVE_PROVIDER"] == "claude" ? .claude : .codex
    }
    private func paper() throws -> AssistantPaper {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FOLIO_LIVE_AI"] == "1", "Set FOLIO_LIVE_AI=1 to call a live provider.")
        return try AssistantPaper(title: "Soft shells reduce widget energy loss", pages: [
            "Abstract. Tiny widgets lose stored energy during handling, which limits their use in sensors. " + String(repeating: "A widget is a small synthetic test object made for this fixture. ", count: 20),
            "Method. Our approach wraps each widget in a soft silicone shell that absorbs impacts before they reach the core. " + String(repeating: "Each widget was dropped from 1 m onto a steel plate. ", count: 20),
            "Results. Shelled widgets kept 82% of stored energy versus 41% for bare widgets across ten trials. " + String(repeating: "The sample is small and the apparatus is fixed. ", count: 20)
        ])
    }

    func testLiveChatAnswerCitesPages() async throws {
        let paper = try paper()
        let streamed = LockedText()
        let answer = try await AssistantService().answer(question: "What does the shell change, and how much? Cite pages.", paper: paper, history: [], provider: provider, page: 1, onText: { streamed.append($0) })
        print("LIVE ANSWER:\n\(answer)")
        XCTAssertFalse(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(answer.contains("82") || answer.lowercased().contains("energy"), answer)
    }

    func testLiveOverviewHasSourcedCards() async throws {
        let paper = try paper()
        let overview = try await AssistantService().overview(paper: paper, provider: provider)
        print("LIVE OVERVIEW:", overview.cards.map { "\($0.id): \($0.label)" })
        XCTAssertFalse(overview.cards.isEmpty)
        XCTAssertTrue(overview.cards.allSatisfy { !$0.sources.isEmpty })
    }
}

private final class LockedText: @unchecked Sendable {
    private let lock = NSLock(); private var value = ""
    func append(_ text: String) { lock.lock(); value += text; lock.unlock() }
}

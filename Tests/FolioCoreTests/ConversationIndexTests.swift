import XCTest
@testable import FolioCore

final class ConversationIndexTests: XCTestCase {
    func testSearchAcrossPaperTitlesThreadTitlesAndAllTurnsWithCorruptionIsolation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = UUID(), second = UUID(), corrupt = UUID()
        var saved = AssistantThreads(paperID: first, fingerprint: "abc")
        saved.append(question: "Explain gradients", answer: "The derivative measures change", titleSource: "Learning")
        let expectedID = try XCTUnwrap(saved.activeID)
        try AssistantThreadRepository(root: root, paperID: first, fingerprint: "abc").save(saved)
        let paper = try AssistantPaper(title: "Legacy", pages: ["Local evidence"])
        let legacy = AssistantRepository(root: root, paperID: second, paper: paper)
        var snapshot = AssistantSnapshot(paperID: second, paper: paper)
        snapshot.turns = [AssistantTurn(role: .user, content: "Earlier question"), AssistantTurn(role: .assistant, content: "Earlier answer")]
        try legacy.save(snapshot)
        let badURL = root.appendingPathComponent("Assistant/\(corrupt.uuidString).threads.json")
        try Data("broken".utf8).write(to: badURL)
        let result = ConversationIndex.load(root: root, papers: [(first, "Optimization"), (second, "Legacy"), (corrupt, "Broken")])
        XCTAssertEqual(result.failures, 1)
        XCTAssertEqual(result.entries.count, 2)
        let entry = try XCTUnwrap(result.entries.first { $0.id == expectedID })
        for query in ["optimization", "LEARNING", "derivative", "gradients", "  "] { XCTAssertTrue(entry.matches(query)) }
        XCTAssertFalse(entry.matches("unrelated"))
        XCTAssertTrue(result.entries.contains { $0.id == second })
        let migrated = try AssistantThreadRepository(root: root, paperID: second, fingerprint: paper.fingerprint).load(legacyTurns: snapshot.turns)
        XCTAssertEqual(migrated.activeID, second)
        XCTAssertEqual(try Data(contentsOf: badURL), Data("broken".utf8))
    }
}

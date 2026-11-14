import XCTest
@testable import FolioCore

final class ConceptGraphTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FolioConceptGraphTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func paper() throws -> AssistantPaper {
        try AssistantPaper(title: "Disposable concept fixture", pages: [
            "The problem concerns a widget signal. " + String(repeating: "A widget signal moves through the system. ", count: 90),
            "Our method uses a small signal model. " + String(repeating: "The model is evaluated on fixture samples. ", count: 90)
        ])
    }

    private func graphJSON(ids: [Int] = [0, 1, 2, 3]) -> String {
        """
        {"nodes":[
          {"id":"problem","label":"Widget signal problem","kind":"problem","explanation":"The paper studies a widget signal.","source_ids":[\(ids[0])]},
          {"id":"model","label":"Compact signal model","kind":"idea","explanation":"The model describes the paper's proposed method.","source_ids":[\(ids[1])]},
          {"id":"evaluation","label":"Fixture sample evaluation","kind":"method","explanation":"The paper evaluates its model on fixture samples.","source_ids":[\(ids[2])]},
          {"id":"result","label":"Reported signal result","kind":"finding","explanation":"The cited passage reports the observed result.","source_ids":[\(ids[3])]}
        ],"edges":[
          {"source":"problem","target":"model","label":"motivates","explanation":"The model addresses the stated problem.","source_ids":[\(ids[0]),\(ids[1])]},
          {"source":"model","target":"evaluation","label":"tested by","explanation":"The paper evaluates the model.","source_ids":[\(ids[1]),\(ids[2])]},
          {"source":"evaluation","target":"result","label":"reports","explanation":"The evaluation reports the cited result.","source_ids":[\(ids[2]),\(ids[3])]}
        ]}
        """
    }

    func testParserUsesExactSelectedPassagesAndRejectsInventedOrBooleanIDs() throws {
        let paper = try paper(), id = UUID(), allowed = Set(paper.passages.prefix(4).map(\.id))
        let graph = try ConceptGraph.parse(graphJSON(), paper: paper, paperID: id, provider: .codex, allowedSourceIDs: allowed)
        XCTAssertEqual(graph.nodes.count, 4)
        XCTAssertEqual(graph.edges.count, 3)
        XCTAssertEqual(graph.nodes[0].sources.first, paper.passages[0])
        XCTAssertEqual(graph.candidatePassages.map(\.id), Array(allowed).sorted())

        XCTAssertThrowsError(try ConceptGraph.parse(graphJSON(ids: [0, 1, 2, 999]), paper: paper, paperID: id, provider: .codex))
        XCTAssertThrowsError(try ConceptGraph.parse(graphJSON().replacingOccurrences(of: "[0]", with: "[true]"), paper: paper, paperID: id, provider: .codex))
        XCTAssertThrowsError(try ConceptGraph.parse(graphJSON(), paper: paper, paperID: id, provider: .codex, allowedSourceIDs: [0, 1, 2]))
    }

    func testParserRequiresConnectedBoundedGraphAndStrictFields() throws {
        let paper = try paper(), id = UUID()
        let valid = graphJSON()
        let disconnected = valid.replacingOccurrences(of: #"{"source":"problem","target":"model","label":"motivates","explanation":"The model addresses the stated problem.","source_ids":[0,1]}"#,
                                                      with: #"{"source":"evaluation","target":"model","label":"motivates","explanation":"The model addresses the stated problem.","source_ids":[0,1]}"#)
        XCTAssertNoThrow(try ConceptGraph.parse(valid, paper: paper, paperID: id, provider: .claude))
        XCTAssertThrowsError(try ConceptGraph.parse(disconnected, paper: paper, paperID: id, provider: .claude))
        XCTAssertThrowsError(try ConceptGraph.parse(valid.replacingOccurrences(of: #""kind":"problem""#, with: #""kind":"generic""#), paper: paper, paperID: id, provider: .claude))
        XCTAssertThrowsError(try ConceptGraph.parse(valid.replacingOccurrences(of: #""edges":["#, with: #""edges":[{"extra":true,"source":"problem","target":"model","label":"x","explanation":"y","source_ids":[0]},"#), paper: paper, paperID: id, provider: .claude))
    }

    func testPersistenceRestoresAndFailsClosedOnCorruptionOrChangedText() throws {
        let root = try directory(), paper = try paper(), id = UUID()
        let graph = try ConceptGraph.parse(graphJSON(), paper: paper, paperID: id, provider: .codex, allowedSourceIDs: Set(paper.passages.prefix(4).map(\.id)))
        let repository = ConceptGraphRepository(root: root, paperID: id, paper: paper)
        XCTAssertNil(try repository.load())
        try repository.save(graph)
        XCTAssertEqual(try repository.load(), graph)
        let bytes = try Data(contentsOf: repository.url)

        let changed = try AssistantPaper(title: paper.title, pages: ["Changed paper text", "Changed second page"])
        XCTAssertThrowsError(try ConceptGraphRepository(root: root, paperID: id, paper: changed).load())
        XCTAssertThrowsError(try ConceptGraphRepository(root: root, paperID: id, paper: changed).save(graph))
        XCTAssertEqual(try Data(contentsOf: repository.url), bytes)

        let corrupt = Data("not json".utf8)
        try corrupt.write(to: repository.url)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(graph))
        XCTAssertEqual(try Data(contentsOf: repository.url), corrupt)
    }
}

import XCTest
import FolioCore
@testable import FolioMac

final class ConceptGraphSelectionTests: XCTestCase {
    @MainActor
    func testRequestsSelectAtMostFortyDistributedPassages() throws {
        let paper = try AssistantPaper(title: "Disposable fixture", pages: (0..<50).map { page in
            String(repeating: "Disposable passage for page \(page). ", count: 10)
        })
        let selected = PaperConceptGraphModel.selectedPassages(paper.passages)
        XCTAssertGreaterThan(paper.passages.count, 40)
        XCTAssertEqual(selected.count, 40)
        XCTAssertEqual(selected.first, paper.passages.first)
        XCTAssertEqual(selected.last, paper.passages.last)
        XCTAssertEqual(Set(selected.map(\.id)).count, selected.count)
        XCTAssertEqual(PaperConceptGraphModel.selectedPassages(Array(paper.passages.prefix(12))).count, 12)
    }
}

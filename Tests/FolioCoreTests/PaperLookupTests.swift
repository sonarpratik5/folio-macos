import XCTest
@testable import FolioCore

final class PaperLookupTests: XCTestCase {
    func testPageContinuationAndTruncationAreExplicit() throws {
        let paper = try PaperLookup(pages: [String(repeating: "a", count: 12_010), ""], truncated: [true, false])
        let first = paper.call("read_paper_page", arguments: ["page": 1])
        XCTAssertEqual((first["text"] as? String)?.count, 12_000)
        XCTAssertEqual(first["nextStart"] as? Int, 12_000)
        XCTAssertEqual(first["truncated"] as? Bool, true)
        let tail = paper.call("read_paper_page", arguments: ["page": 1, "start": 12_000])
        XCTAssertEqual((tail["text"] as? String)?.count, 10)
        XCTAssertTrue(tail["nextStart"] is NSNull)
        XCTAssertNotNil(paper.call("read_paper_page", arguments: ["page": 2])["note"])
    }

    func testSearchIncludesAppendixAndRanksMatchingTerms() throws {
        let paper = try PaperLookup(pages: ["An opening baseline.", "Appendix: baseline ablation evidence.", "Unrelated text."], truncated: [false, false, false])
        let response = paper.call("search_paper", arguments: ["query": "baseline ablation"])
        let hits = try XCTUnwrap(response["results"] as? [[String: Any]])
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits.first?["page"] as? Int, 2)
        XCTAssertEqual(hits.first?["text"] as? String, "Appendix: baseline ablation evidence.")
    }

    func testRejectsUnscopedArgumentsAndMalformedCorpus() throws {
        XCTAssertThrowsError(try PaperLookup(pages: ["text"], truncated: []))
        XCTAssertThrowsError(try PaperLookup(pages: [String(repeating: "a", count: PaperLookup.maximumBytes)], truncated: [false]))
        let paper = try PaperLookup(pages: ["text"], truncated: [false])
        for args: [String: Any] in [["page": 0], ["page": 1.5], ["page": true], ["page": 1, "path": "/tmp/other"], ["page": 1, "start": 99]] {
            XCTAssertNotNil(paper.call("read_paper_page", arguments: args)["error"])
        }
        XCTAssertNotNil(paper.call("search_paper", arguments: ["query": "x", "path": "other"])["error"])
        XCTAssertNotNil(paper.call("shell", arguments: [:])["error"])
    }
}

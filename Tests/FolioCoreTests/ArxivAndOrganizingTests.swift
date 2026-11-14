import XCTest
@testable import FolioCore

final class ArxivAndOrganizingTests: XCTestCase {
    func testParsesIdsAndLinks() {
        XCTAssertEqual(ArxivID.parse("2401.12345"), "2401.12345")
        XCTAssertEqual(ArxivID.parse("arXiv:2401.12345v2"), "2401.12345v2")
        XCTAssertEqual(ArxivID.parse("https://arxiv.org/abs/2401.12345v3"), "2401.12345v3")
        XCTAssertEqual(ArxivID.parse("https://export.arxiv.org/pdf/2401.1234.pdf"), "2401.1234")
        XCTAssertEqual(ArxivID.parse("arxiv.org/html/2401.12345/"), "2401.12345")
        XCTAssertEqual(ArxivID.parse("hep-th/9901001"), "hep-th/9901001")
        XCTAssertEqual(ArxivID.parse("https://arxiv.org/abs/math.GT/0309136"), "math.GT/0309136")
        XCTAssertNil(ArxivID.parse("https://evil.com/abs/2401.12345"))
        XCTAssertNil(ArxivID.parse("https://arxiv.org.evil.com/abs/2401.12345"))
        XCTAssertNil(ArxivID.parse("ftp://arxiv.org/abs/2401.12345"))
        XCTAssertNil(ArxivID.parse("hello"))
        XCTAssertNil(ArxivID.parse(""))
    }

    func testFileNameAndAtom() {
        XCTAssertEqual(ArxivID.fileName(id: "hep-th/9901001", title: "A/B: Study?"), "AB Study (arXiv hep-th_9901001).pdf")
        XCTAssertEqual(ArxivID.fileName(id: "2401.12345", title: nil), "arXiv 2401.12345.pdf")
        let xml = "<feed><title>feed</title><entry><id>x</id><title>Attention &amp; \n  Memory</title></entry></feed>"
        XCTAssertEqual(ArxivID.atomTitle(xml), "Attention & Memory")
    }

    func testPDFMagic() {
        XCTAssertTrue(ArxivDownloader.looksLikePDF(Data("%PDF-1.7\n".utf8)))
        XCTAssertFalse(ArxivDownloader.looksLikePDF(Data("<html>".utf8)))
    }

    func testSortAndFilter() {
        var a = PaperRecord(title: "Beta", pageCount: 5, author: "Zed")
        var b = PaperRecord(title: "alpha", pageCount: 5, author: "Amy")
        let c = PaperRecord(title: "Gamma", pageCount: 5)
        a.lastOpened = Date(timeIntervalSince1970: 300); b.lastOpened = Date(timeIntervalSince1970: 200)
        a.addedAt = Date(timeIntervalSince1970: 10); b.addedAt = Date(timeIntervalSince1970: 20)
        a.currentPage = 3; a.starredPages = [2]
        let all = [a, b, c]
        XCTAssertEqual(LibraryOrganizer.apply(all, order: .title).map(\.title), ["alpha", "Beta", "Gamma"])
        XCTAssertEqual(LibraryOrganizer.apply(all, order: .author).map(\.title), ["alpha", "Beta", "Gamma"])
        XCTAssertEqual(LibraryOrganizer.apply(all, order: .recentlyOpened).first?.title, "Gamma")
        XCTAssertEqual(LibraryOrganizer.apply([a, b], order: .added).first?.title, "alpha")
        XCTAssertEqual(LibraryOrganizer.apply(all, filter: .starred, order: .title).map(\.title), ["Beta"])
        XCTAssertEqual(Set(LibraryOrganizer.apply(all, filter: .unread, order: .title).map(\.title)), ["alpha", "Gamma"])
        XCTAssertEqual(LibraryOrganizer.apply(all, filter: .withNotes, order: .title, noteCounts: [b.id: 2]).map(\.title), ["alpha"])
        XCTAssertEqual(LibraryOrganizer.apply(all, query: "zed", order: .title).map(\.title), ["Beta"])
    }
}

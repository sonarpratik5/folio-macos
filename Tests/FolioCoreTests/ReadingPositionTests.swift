import XCTest
import FolioCore

final class ReadingPositionTests: XCTestCase {
    func testStoreRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try ReadingPositionStore(root: root).set(ReadingPosition(zoom: 1.5, fit: "custom", layout: "two", rotation: 90), for: id)
        let loaded = ReadingPositionStore(root: root).position(for: id)
        XCTAssertEqual(loaded, ReadingPosition(zoom: 1.5, fit: "custom", layout: "two", rotation: 90))
        XCTAssertNil(ReadingPositionStore(root: root).position(for: UUID()))
    }

    func testSearchNormalizationJoinsHyphenatedLineBreaks() {
        let source = "A  Caf\u{E9} on the Hel-\nlo   world"
        let text = NormalizedSearchText(source)
        XCTAssertEqual(text.text, "a cafe on the hello world")
        let hello = text.matches(of: "hello")
        XCTAssertEqual(hello.count, 1)
        XCTAssertEqual((source as NSString).substring(with: hello[0]), "Hel-\nlo")
        let cafe = text.matches(of: NormalizedSearchText("CAFE").text)
        XCTAssertEqual((source as NSString).substring(with: cafe[0]), "Caf\u{E9}")
        XCTAssertEqual(text.matches(of: "on the hel").count, 1)
    }
}

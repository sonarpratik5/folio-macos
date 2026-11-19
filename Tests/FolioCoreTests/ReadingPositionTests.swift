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

    func testSearchNormalizationPreservesUnicodeAndOriginalOffsets() {
        let source = "  ASCII I-i, e\u{301} CAFÉ Straße 👩🏽‍🔬 中文 co\u{AD}operate multi-\r\nmodal\tEND  "
        let normalized = NormalizedSearchText(source)
        for (query, original) in [("ascii i-i", "ASCII I-i"), ("e cafe", "e\u{301} CAFÉ"),
                                  ("strasse", "Straße"), ("👩🏽‍🔬", "👩🏽‍🔬"), ("中文", "中文"),
                                  ("cooperate", "co\u{AD}operate"), ("multimodal", "multi-\r\nmodal"), ("end", "END")] {
            let ranges = normalized.matches(of: NormalizedSearchText(query).text)
            XCTAssertEqual(ranges.count, 1, query)
            if let range = ranges.first { XCTAssertEqual((source as NSString).substring(with: range), original, query) }
        }
        let ascii = String((0x21...0x7E).map { Character(UnicodeScalar($0)!) })
        XCTAssertEqual(NormalizedSearchText(ascii).text, ascii.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }

    func testSearchNormalizationPerformance() {
        let source = String(repeating: "Abstract: We evaluate RESEARCH methods on 120 samples. Results show reproducible gains in accuracy, with cafe\u{E9} and hyphen-\nated text preserved.\n", count: 400)
        measure {
            let normalized = NormalizedSearchText(source)
            XCTAssertEqual(normalized.matches(of: "research").count, 400)
        }
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
    func testFailedWriteDoesNotPoisonIdenticalRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReadingPositionStore(root: root), id = UUID()
        let before = ReadingPosition(zoom: 1), after = ReadingPosition(zoom: 2)
        try store.set(before, for: id)
        let file = root.appendingPathComponent("reading-positions.json")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.set(after, for: id))
        XCTAssertEqual(store.position(for: id), before)
        try FileManager.default.removeItem(at: file)
        try store.set(after, for: id)
        XCTAssertEqual(ReadingPositionStore(root: root).position(for: id), after)
    }

    func testMalformedStoreIsPreservedUntilRepaired() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("reading-positions.json")
        let bytes = Data("truncated JSON".utf8)
        try bytes.write(to: file)
        let store = ReadingPositionStore(root: root), id = UUID()
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.set(ReadingPosition(), for: id))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        try Data("{}".utf8).write(to: file)
        try store.set(ReadingPosition(), for: id)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(ReadingPositionStore(root: root).position(for: id), ReadingPosition())
    }

    func testDuplicateUUIDSpellingsFailClosedWithoutTrap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = "ABCDEFAB-1234-5678-9012-ABCDEFABCDEF"
        let values = [id: ReadingPosition(), id.lowercased(): ReadingPosition(zoom: 2)]
        let bytes = try JSONEncoder().encode(values)
        let file = root.appendingPathComponent("reading-positions.json")
        try bytes.write(to: file)
        let store = ReadingPositionStore(root: root)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.set(ReadingPosition(), for: UUID()))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

}

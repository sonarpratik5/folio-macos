import Foundation

/// View state remembered per paper (page itself lives in `PaperRecord.currentPage`).
public struct ReadingPosition: Codable, Equatable {
    public var zoom: Double?
    public var fit: String
    public var layout: String
    public var rotation: Int

    public init(zoom: Double? = nil, fit: String = "page", layout: String = "singleContinuous", rotation: Int = 0) {
        self.zoom = zoom; self.fit = fit; self.layout = layout; self.rotation = rotation
    }
}

/// Local, atomic JSON store for reading positions, kept next to the library manifest.
public final class ReadingPositionStore {
    private let url: URL
    private var positions: [UUID: ReadingPosition] = [:]
    public private(set) var loadError: Error?

    public init(root: URL) {
        url = root.appendingPathComponent("reading-positions.json")
        do { positions = try readPositions() } catch { loadError = error }
    }

    private func readPositions() throws -> [UUID: ReadingPosition] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let decoded = try JSONDecoder().decode([String: ReadingPosition].self, from: Data(contentsOf: url))
        var result: [UUID: ReadingPosition] = [:]
        for (key, value) in decoded {
            guard let id = UUID(uuidString: key), result[id] == nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
            result[id] = value
        }
        return result
    }

    public func position(for id: UUID) -> ReadingPosition? { positions[id] }

    public func set(_ position: ReadingPosition, for id: UUID) throws {
        // Recheck after an external repair; never replace an unreadable store with an empty one.
        if loadError != nil {
            do { positions = try readPositions(); loadError = nil }
            catch { loadError = error; throw error }
        }
        guard positions[id] != position else { return }
        var next = positions
        next[id] = position
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Dictionary(uniqueKeysWithValues: next.map { ($0.key.uuidString, $0.value) }))
        try data.write(to: url, options: .atomic)
        positions = next
    }
}

/// Search-text normalisation shared by the reader search: folds case and diacritics, collapses
/// whitespace, drops soft hyphens and rejoins words hyphenated across a line break, while keeping
/// a map back to the original UTF-16 offsets so matches can be highlighted in the PDF.
public struct NormalizedSearchText {
    public let text: String
    private let units: NSString
    private let starts: [Int]
    private let ends: [Int]

    public init(_ source: String) {
        let ns = source as NSString
        var out = "", starts: [Int] = [], ends: [Int] = []
        func isSpace(_ u: unichar) -> Bool { u == 0x20 || u == 0xA0 || (u >= 0x9 && u <= 0xD) || u == 0x2028 || u == 0x2029 }
        func isLetter(_ u: unichar) -> Bool { Character(UnicodeScalar(u) ?? " ").isLetter }
        var i = 0
        while i < ns.length {
            let u = ns.character(at: i)
            if u == 0xAD { i += 1; continue }
            if isSpace(u) {
                var j = i
                while j < ns.length, isSpace(ns.character(at: j)) { j += 1 }
                out += " "; starts.append(i); ends.append(j); i = j; continue
            }
            if u == 0x2D || u == 0x2010, i > 0, isLetter(ns.character(at: i - 1)) {
                var j = i + 1, newline = false
                while j < ns.length, isSpace(ns.character(at: j)) {
                    if ns.character(at: j) == 0xA || ns.character(at: j) == 0xD { newline = true }
                    j += 1
                }
                if newline, j < ns.length, isLetter(ns.character(at: j)) { i = j; continue }
            }
            // ASCII before another ASCII unit cannot start a combining sequence.
            // Keep the composed-character path at Unicode boundaries (e.g. e + acute).
            if u >= 0x21, u <= 0x7E, i + 1 == ns.length || ns.character(at: i + 1) < 0x80 {
                let folded = u >= 0x41 && u <= 0x5A ? u + 0x20 : u
                out.unicodeScalars.append(UnicodeScalar(folded)!)
                starts.append(i); ends.append(i + 1); i += 1
                continue
            }
            let range = ns.rangeOfComposedCharacterSequence(at: i)
            let folded = ns.substring(with: range).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            for unit in folded.utf16 { starts.append(range.location); ends.append(NSMaxRange(range)); _ = unit }
            out += folded
            i = NSMaxRange(range)
        }
        var trimmed = out
        var lead = 0
        while trimmed.hasPrefix(" ") { trimmed.removeFirst(); lead += 1 }
        while trimmed.hasSuffix(" ") { trimmed.removeLast() }
        text = trimmed
        units = trimmed as NSString
        self.starts = Array(starts.dropFirst(lead).prefix(trimmed.utf16.count))
        self.ends = Array(ends.dropFirst(lead).prefix(trimmed.utf16.count))
    }

    /// Ranges in the original string for every non-overlapping match of `query` (already normalised).
    public func matches(of query: String) -> [NSRange] {
        guard !query.isEmpty, units.length >= (query as NSString).length else { return [] }
        var result: [NSRange] = []
        var search = NSRange(location: 0, length: units.length)
        while search.length > 0 {
            let found = units.range(of: query, options: [], range: search)
            if found.location == NSNotFound { break }
            result.append(NSRange(location: starts[found.location], length: ends[NSMaxRange(found) - 1] - starts[found.location]))
            search = NSRange(location: NSMaxRange(found), length: units.length - NSMaxRange(found))
        }
        return result
    }
}

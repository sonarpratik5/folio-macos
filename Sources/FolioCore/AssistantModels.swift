import Foundation
import CryptoKit
import CoreFoundation

public enum AssistantProvider: String, Codable, CaseIterable, Identifiable {
    case codex = "codex-cli", claude = "claude-api"
    public var id: String { rawValue }
    public var name: String { self == .codex ? "Codex CLI" : "Claude API" }
    public var model: String { self == .codex ? "gpt-6.1-terra" : ClaudeKeyStore.model() }
}

public enum AssistantError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let message): message } }
    public static let invalidData = AssistantError.message("The saved assistant data could not be read. Its file was left untouched.")
    public static let invalidOverview = AssistantError.message("The model returned an overview with invalid formatting or sources. Try again.")
}

public struct AssistantTurn: Codable, Identifiable, Equatable {
    public enum Role: String, Codable { case user, assistant }
    public let id: UUID
    public let role: Role
    public let content: String
    public let createdAt: Date
    public init(role: Role, content: String) { id = UUID(); self.role = role; self.content = content; createdAt = Date() }
}

public struct AssistantPassage: Codable, Equatable, Identifiable {
    public let id: Int
    public let page: Int
    public let text: String
}

public struct AssistantPaper {
    public let title: String
    public let pageCount: Int
    public let passages: [AssistantPassage]
    public let totalPassages: Int
    public let sampled: Bool
    public let fingerprint: String
    public let lookupPages: [String]
    public let truncatedPages: [Bool]

    /// Deterministic distributed excerpts; bounded per-page extraction stays available to paper tools.
    public init(title: String, pages: [String]) throws {
        guard !pages.isEmpty, pages.count <= 10_000 else { throw AssistantError.message("This PDF has too many pages for the assistant.") }
        self.title = String(title.prefix(300)); pageCount = pages.count
        let maxPage = min(60_000, max(600, 6_000_000 / pages.count))
        // Match the helper's actual encoded-byte budget, including JSON escaping and
        // multibyte scripts. Each page retains a fair share instead of dropping later pages.
        let perPageBytes = max(2, (PaperLookup.maximumBytes - 2) / pages.count - 2)
        lookupPages = pages.map { source in
            let candidate = String(source.prefix(maxPage))
            guard (try? JSONEncoder().encode(candidate).count) ?? Int.max > perPageBytes else { return candidate }
            var low = 0, high = candidate.count
            while low < high {
                let middle = (low + high + 1) / 2
                let size = (try? JSONEncoder().encode(String(candidate.prefix(middle))).count) ?? Int.max
                if size <= perPageBytes { low = middle } else { high = middle - 1 }
            }
            return String(candidate.prefix(low))
        }
        truncatedPages = zip(pages, lookupPages).map { $0.count > $1.count }
        var hash = SHA256()
        for page in pages {
            let bytes = Data(page.utf8)
            hash.update(data: Data("\(bytes.count):".utf8)); hash.update(data: bytes)
        }
        fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
        var buckets: [[AssistantPassage]] = []; var nextID = 0
        for (index, page) in lookupPages.enumerated() {
            let text = page.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            var remaining = text[...]; var bucket: [AssistantPassage] = []
            while !remaining.isEmpty {
                var end = remaining.index(remaining.startIndex, offsetBy: min(1200, remaining.count))
                if end != remaining.endIndex, let space = remaining[..<end].lastIndex(of: " "), remaining.distance(from: remaining.startIndex, to: space) > 600 { end = space }
                let part = String(remaining[..<end]).trimmingCharacters(in: .whitespaces)
                if !part.isEmpty { bucket.append(AssistantPassage(id: nextID, page: index + 1, text: part)); nextID += 1 }
                remaining = remaining[end...].drop(while: { $0.isWhitespace })
            }
            buckets.append(bucket)
        }
        totalPassages = nextID
        guard nextID > 0 else { throw AssistantError.message("This PDF has no selectable text. Scanned PDFs need OCR before using the assistant.") }
        var selected: [AssistantPassage] = []; var seen = Set<Int>(); var used = 0
        func take(_ passage: AssistantPassage) {
            guard !seen.contains(passage.id), selected.count < 800, used + Self.quoted(passage.text).utf8.count + 80 <= 40_000 else { return }
            selected.append(passage); seen.insert(passage.id); used += Self.quoted(passage.text).utf8.count + 80
        }
        buckets.flatMap { $0 }.prefix(3).forEach(take)
        // Visit both ends and evenly distributed interior pages before adjacent pages,
        // so a short budget still reaches the end of a very long paper.
        var pageOrder = [0]; var intervals: [(Int, Int)] = []
        if buckets.count > 1 { pageOrder.append(buckets.count - 1); intervals.append((0, buckets.count - 1)) }
        var intervalIndex = 0
        while intervalIndex < intervals.count {
            let (low, high) = intervals[intervalIndex]; intervalIndex += 1
            guard high - low > 1 else { continue }
            let middle = (low + high) / 2; pageOrder.append(middle)
            intervals.append((low, middle)); intervals.append((middle, high))
        }
        for depth in 0..<(buckets.map(\.count).max() ?? 0) { for index in pageOrder where depth < buckets[index].count { take(buckets[index][depth]) } }
        passages = selected.sorted { $0.id < $1.id }
        sampled = selected.count != nextID || truncatedPages.contains(true)
    }

    public var context: String { passages.map { "[S\($0.id) p\($0.page)] \(Self.quoted($0.text))" }.joined(separator: "\n") }
    /// Small opening map for chat; exact evidence stays in the request-scoped lookup tools.
    public var chatContext: String {
        let budget = 12_000
        let header = "Paper map: opening excerpts only, not complete evidence. Read or search exact pages when needed. Omitted text is not evidence of absence.\n\n"
        let count = min(pageCount, max(1, 1 + (budget - header.count - 2500) / 350))
        let indices = (0..<count).map { count == 1 ? 0 : Int((Double($0) * Double(pageCount - 1) / Double(count - 1)).rounded()) }
        let blocks = indices.map { index -> String in
            let text = lookupPages[index].split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let limit = index == 0 ? 2400 : 320
            let excerpt = String(text.prefix(limit)) + (text.count > limit ? " …" : "")
            return "[Page \(index + 1)]\(truncatedPages[index] ? " [extraction truncated]" : "")\n\(text.isEmpty ? "No selectable text; images/scans need OCR." : excerpt)"
        }
        return String((header + blocks.joined(separator: "\n\n")).prefix(budget))
    }
    /// A small local window resolves ambiguous terms without sending the whole focus page.
    /// Never substitute unrelated page text when the selected passage cannot be located.
    public func selectionContext(_ selection: String, page: Int) -> String? {
        guard (1...pageCount).contains(page) else { return nil }
        let normalize: (String) -> String = { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        let text = normalize(lookupPages[page - 1]), needle = normalize(selection)
        guard !needle.isEmpty, needle.count <= 12_000,
              let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -600, limitedBy: text.startIndex) ?? text.startIndex
        if needle.count > 800 {
            let end = text.index(range.upperBound, offsetBy: 600, limitedBy: text.endIndex) ?? text.endIndex
            return String(text[start..<range.lowerBound]) + " [selected passage omitted here] " + String(text[range.upperBound..<end])
        }
        let end = text.index(start, offsetBy: 1600, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end])
    }
    public var coverage: String { "\(sampled ? "Sampled excerpts" : "All extracted text"): \(passages.count) of \(totalPassages) passages across \(Set(passages.map(\.page)).count) of \(pageCount) pages." }
    public static func quoted(_ text: String) -> String { (try? String(data: JSONEncoder().encode(text), encoding: .utf8)) ?? "\"\"" }
}

public struct AssistantOverview: Codable, Equatable {
    public struct Card: Codable, Identifiable, Equatable {
        public let id: String
        public let label: String
        public let explanation: String
        public let sources: [AssistantPassage]
    }
    public let cards: [Card]
    public let provider: AssistantProvider
    public let model: String
    public let createdAt: Date
    public let coverage: String

    public static func parse(_ output: String, paper: AssistantPaper, provider: AssistantProvider) throws -> AssistantOverview {
        guard let data = output.data(using: .utf8), let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any], Set(raw.keys) == Set(["problem", "approach", "finding"]) else { throw AssistantError.invalidOverview }
        var cards: [Card] = []
        for role in ["problem", "approach", "finding"] {
            guard let value = raw[role] as? [String: Any], Set(value.keys) == Set(["available", "label", "explanation", "sentence_ids"]),
                  let availability = value["available"] as? NSNumber, CFGetTypeID(availability) == CFBooleanGetTypeID(),
                  let label = value["label"] as? String, let explanation = value["explanation"] as? String,
                  let numbers = value["sentence_ids"] as? [NSNumber], numbers.allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && $0.doubleValue >= 0 && $0.doubleValue < 100_000 && $0.doubleValue == Double($0.intValue) }) else { throw AssistantError.invalidOverview }
            let available = availability.boolValue
            let refs = numbers.map(\.intValue)
            if !available { guard label.isEmpty, explanation.isEmpty, refs.isEmpty else { throw AssistantError.invalidOverview }; continue }
            let cleanLabel = label.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let cleanExplanation = explanation.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !cleanLabel.isEmpty, cleanLabel.count <= 62, cleanLabel.split(separator: " ").count <= 8,
                  !cleanExplanation.isEmpty, cleanExplanation.count <= 450, cleanExplanation.split(separator: " ").count <= 60,
                  (1...3).contains(refs.count), Set(refs).count == refs.count else { throw AssistantError.invalidOverview }
            let sources = refs.compactMap { ref in paper.passages.first { $0.id == ref } }
            guard sources.count == refs.count else { throw AssistantError.invalidOverview }
            cards.append(Card(id: role, label: cleanLabel, explanation: cleanExplanation, sources: sources))
        }
        guard !cards.isEmpty else { throw AssistantError.message("The supplied paper text did not support an overview.") }
        return AssistantOverview(cards: cards, provider: provider, model: provider.model, createdAt: Date(), coverage: paper.coverage)
    }
}

public struct AssistantSnapshot: Codable {
    public var schemaVersion = 1
    public let paperID: UUID
    public let pageCount: Int
    public let fingerprint: String
    public var turns: [AssistantTurn] = []
    public var overview: AssistantOverview?
    public init(paperID: UUID, paper: AssistantPaper) { self.paperID = paperID; pageCount = paper.pageCount; fingerprint = paper.fingerprint }
}

public final class AssistantRepository {
    public let url: URL
    private let paperID: UUID
    private let paper: AssistantPaper
    public init(root: URL, paperID: UUID, paper: AssistantPaper) {
        self.paperID = paperID; self.paper = paper
        url = root.appendingPathComponent("Assistant", isDirectory: true).appendingPathComponent(paperID.uuidString).appendingPathExtension("json")
    }
    public func load() throws -> AssistantSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return AssistantSnapshot(paperID: paperID, paper: paper) }
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber, size.intValue <= 8_000_000,
              let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(AssistantSnapshot.self, from: data) else { throw AssistantError.invalidData }
        try validate(saved)
        guard saved.fingerprint == paper.fingerprint else { throw AssistantError.message("The PDF text changed after this conversation was saved. Its assistant data was left untouched.") }
        return saved
    }
    public func save(_ snapshot: AssistantSnapshot) throws {
        try validate(snapshot)
        // A malformed existing file must never be silently replaced by a fresh session.
        if FileManager.default.fileExists(atPath: url.path) { _ = try load() }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 8_000_000 else { throw AssistantError.message("This conversation is too large to save.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private func validate(_ value: AssistantSnapshot) throws {
        guard value.schemaVersion == 1, value.paperID == paperID, value.pageCount == paper.pageCount, value.fingerprint == paper.fingerprint,
              value.turns.count <= 96, value.turns.count.isMultiple(of: 2), Set(value.turns.map(\.id)).count == value.turns.count,
              value.turns.enumerated().allSatisfy({ index, turn in turn.role == (index.isMultiple(of: 2) ? .user : .assistant) && !turn.content.isEmpty && turn.content.count <= 64_000 && turn.createdAt.timeIntervalSince1970.isFinite }) else { throw AssistantError.invalidData }
        if let overview = value.overview {
            guard (1...3).contains(overview.cards.count), Set(overview.cards.map(\.id)).count == overview.cards.count, overview.model.count <= 100, overview.coverage == paper.coverage,
                  overview.createdAt.timeIntervalSince1970.isFinite else { throw AssistantError.invalidData }
            for card in overview.cards {
                guard ["problem", "approach", "finding"].contains(card.id), !card.label.isEmpty, card.label.count <= 62, card.label.split(whereSeparator: { $0.isWhitespace }).count <= 8,
                      !card.explanation.isEmpty, card.explanation.count <= 450, card.explanation.split(whereSeparator: { $0.isWhitespace }).count <= 60,
                      (1...3).contains(card.sources.count), Set(card.sources.map(\.id)).count == card.sources.count,
                      card.sources.allSatisfy({ paper.passages.contains($0) }) else { throw AssistantError.invalidData }
            }
        }
    }
}

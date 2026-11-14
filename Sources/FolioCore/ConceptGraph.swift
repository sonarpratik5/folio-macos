import Foundation
import CoreFoundation

public enum ConceptGraphError: LocalizedError {
    case invalidResponse, unsupportedPaper, invalidSavedData, changedPaper

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The concept map had invalid ideas, connections or sources. Try again."
        case .unsupportedPaper: "There is not enough selectable paper text to build a concept map."
        case .invalidSavedData: "The saved concept map could not be read. Its file was left untouched."
        case .changedPaper: "The PDF text changed after this concept map was saved. The saved map was left untouched."
        }
    }
}

public struct ConceptGraph: Codable, Equatable {
    public struct Idea: Codable, Identifiable, Equatable {
        public let id: String
        public let label: String
        public let kind: String
        public let explanation: String
        public let sources: [AssistantPassage]
    }

    public struct Connection: Codable, Identifiable, Equatable {
        public var id: String { "\(source)>\(target)" }
        public let source: String
        public let target: String
        public let label: String
        public let explanation: String
        public let sources: [AssistantPassage]
    }

    public let schemaVersion: Int
    public let paperID: UUID
    public let pageCount: Int
    public let fingerprint: String
    public let provider: AssistantProvider
    public let model: String
    public let coverage: String
    public let createdAt: Date
    public let candidatePassages: [AssistantPassage]
    public let nodes: [Idea]
    public let edges: [Connection]

    public var sourcePassages: [AssistantPassage] {
        candidatePassages
    }

    /// Parses a model response while resolving every citation to the paper's extracted passages.
    /// Only IDs explicitly supplied in this request may be cited.
    public static func parse(_ output: String, paper: AssistantPaper, paperID: UUID,
                             provider: AssistantProvider, allowedSourceIDs: Set<Int>? = nil) throws -> ConceptGraph {
        guard paper.passages.count >= 2 else { throw ConceptGraphError.unsupportedPaper }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            guard lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true else { throw ConceptGraphError.invalidResponse }
            json = lines.dropFirst().dropLast().joined(separator: "\n")
        } else { json = trimmed }
        guard let data = json.data(using: .utf8), data.count <= 256_000,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], Set(root.keys) == Set(["nodes", "edges"]),
              let rawNodes = root["nodes"] as? [[String: Any]], (2...10).contains(rawNodes.count),
              let rawEdges = root["edges"] as? [[String: Any]], rawEdges.count <= 14 else { throw ConceptGraphError.invalidResponse }

        let passages = Dictionary(uniqueKeysWithValues: paper.passages.map { ($0.id, $0) })
        let allowed = allowedSourceIDs ?? Set(passages.keys)
        func sources(_ raw: Any?) throws -> [AssistantPassage] {
            guard let ids = raw as? [NSNumber], (1...3).contains(ids.count) else { throw ConceptGraphError.invalidResponse }
            var found: [AssistantPassage] = []; var seen = Set<Int>()
            for number in ids {
                // JSON booleans bridge to NSNumber too. Reject them as citation IDs.
                guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                      number.doubleValue.rounded(.towardZero) == number.doubleValue,
                      number.intValue >= 0, seen.insert(number.intValue).inserted,
                      allowed.contains(number.intValue), let passage = passages[number.intValue] else { throw ConceptGraphError.invalidResponse }
                found.append(passage)
            }
            return found
        }
        func clean(_ raw: Any?, limit: Int, words: ClosedRange<Int>) throws -> String {
            guard let rawText = raw as? String else { throw ConceptGraphError.invalidResponse }
            let normalized = rawText.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !normalized.isEmpty, normalized.count <= limit, words.contains(normalized.split(separator: " ").count) else { throw ConceptGraphError.invalidResponse }
            return normalized
        }

        var nodes: [Idea] = []; var nodeIDs = Set<String>()
        let kinds = Set(["context", "problem", "idea", "method", "evidence", "finding", "limitation"])
        for raw in rawNodes {
            guard Set(raw.keys) == Set(["id", "label", "kind", "explanation", "source_ids"]),
                  let id = raw["id"] as? String, id.count <= 40, id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
                  nodeIDs.insert(id).inserted, let kind = raw["kind"] as? String, kinds.contains(kind) else { throw ConceptGraphError.invalidResponse }
            nodes.append(Idea(id: id, label: try clean(raw["label"], limit: 90, words: 2...7), kind: kind,
                              explanation: try clean(raw["explanation"], limit: 700, words: 1...70), sources: try sources(raw["source_ids"])))
        }

        var edges: [Connection] = []; var pairs = Set<String>()
        for raw in rawEdges {
            guard Set(raw.keys) == Set(["source", "target", "label", "explanation", "source_ids"]),
                  let source = raw["source"] as? String, nodeIDs.contains(source),
                  let target = raw["target"] as? String, nodeIDs.contains(target), source != target,
                  pairs.insert(source + ">" + target).inserted else { throw ConceptGraphError.invalidResponse }
            edges.append(Connection(source: source, target: target,
                                    label: try clean(raw["label"], limit: 55, words: 1...8),
                                    explanation: try clean(raw["explanation"], limit: 700, words: 1...70),
                                    sources: try sources(raw["source_ids"])))
        }
        guard isConnected(nodeIDs: nodeIDs, edges: edges) else { throw ConceptGraphError.invalidResponse }
        let candidates = paper.passages.filter { allowed.contains($0.id) }
        guard (2...40).contains(candidates.count) else { throw ConceptGraphError.invalidResponse }
        return ConceptGraph(schemaVersion: 1, paperID: paperID, pageCount: paper.pageCount, fingerprint: paper.fingerprint,
                            provider: provider, model: String(provider.model.prefix(100)), coverage: paper.coverage,
                            createdAt: Date(), candidatePassages: candidates, nodes: nodes, edges: edges)
    }

    private static func isConnected(nodeIDs: Set<String>, edges: [Connection]) -> Bool {
        guard let start = nodeIDs.first else { return false }
        var reached: Set<String> = [start], pending = [start]
        while let current = pending.popLast() {
            for edge in edges {
                let next = edge.source == current ? edge.target : edge.target == current ? edge.source : nil
                if let next, reached.insert(next).inserted { pending.append(next) }
            }
        }
        return reached == nodeIDs
    }
}

/// One map per managed paper; all writes are atomic and corrupt files are never replaced.
public final class ConceptGraphRepository {
    public let url: URL
    private let paperID: UUID
    private let paper: AssistantPaper

    public init(root: URL, paperID: UUID, paper: AssistantPaper) {
        self.paperID = paperID; self.paper = paper
        url = root.appendingPathComponent("Assistant", isDirectory: true)
            .appendingPathComponent("ConceptGraphs", isDirectory: true)
            .appendingPathComponent(paperID.uuidString).appendingPathExtension("json")
    }

    public func load() throws -> ConceptGraph? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.intValue <= 1_000_000, let data = try? Data(contentsOf: url),
              let graph = try? JSONDecoder().decode(ConceptGraph.self, from: data), valid(graph) else { throw ConceptGraphError.invalidSavedData }
        guard graph.fingerprint == paper.fingerprint else { throw ConceptGraphError.changedPaper }
        return graph
    }

    public func save(_ graph: ConceptGraph) throws {
        guard valid(graph) else { throw ConceptGraphError.invalidSavedData }
        if FileManager.default.fileExists(atPath: url.path) { _ = try load() }
        let data = try JSONEncoder().encode(graph)
        guard data.count <= 1_000_000 else { throw ConceptGraphError.invalidSavedData }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func valid(_ graph: ConceptGraph) -> Bool {
        guard graph.schemaVersion == 1, graph.paperID == paperID, graph.pageCount == paper.pageCount,
              graph.fingerprint == paper.fingerprint, graph.provider == .codex || graph.provider == .claude,
              graph.model.count <= 100, graph.coverage == paper.coverage, graph.createdAt.timeIntervalSince1970.isFinite,
              (2...40).contains(graph.candidatePassages.count),
              graph.candidatePassages.allSatisfy(paper.passages.contains),
              graph.candidatePassages.map(\.id).count == Set(graph.candidatePassages.map(\.id)).count,
              (2...10).contains(graph.nodes.count), graph.nodes.count == Set(graph.nodes.map(\.id)).count,
              graph.edges.count <= 14, isGraphConnected(graph),
              graph.nodes.allSatisfy({ node in
                  node.id.count <= 40 && node.id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
                      && ["context", "problem", "idea", "method", "evidence", "finding", "limitation"].contains(node.kind)
                      && !node.label.isEmpty && node.label.count <= 90 && (2...7).contains(node.label.split(separator: " ").count)
                      && !node.explanation.isEmpty && node.explanation.count <= 700 && (1...70).contains(node.explanation.split(separator: " ").count)
                      && (1...3).contains(node.sources.count) && node.sources.map(\.id).count == Set(node.sources.map(\.id)).count
                      && node.sources.allSatisfy({ graph.candidatePassages.contains($0) })
              }),
              graph.edges.allSatisfy({ edge in
                  graph.nodes.contains(where: { $0.id == edge.source }) && graph.nodes.contains(where: { $0.id == edge.target })
                      && edge.source != edge.target && !edge.label.isEmpty && edge.label.count <= 55
                      && !edge.explanation.isEmpty && edge.explanation.count <= 700 && (1...70).contains(edge.explanation.split(separator: " ").count)
                      && (1...8).contains(edge.label.split(separator: " ").count)
                      && (1...3).contains(edge.sources.count) && edge.sources.map(\.id).count == Set(edge.sources.map(\.id)).count
                      && edge.sources.allSatisfy({ graph.candidatePassages.contains($0) })
              }) else { return false }
        guard graph.edges.map(\.id).count == Set(graph.edges.map(\.id)).count else { return false }
        return true
    }

    private func isGraphConnected(_ graph: ConceptGraph) -> Bool {
        let ids = Set(graph.nodes.map(\.id))
        guard let start = ids.first else { return false }
        var reached: Set<String> = [start], pending = [start]
        while let current = pending.popLast() {
            for edge in graph.edges {
                let next = edge.source == current ? edge.target : edge.target == current ? edge.source : nil
                if let next, reached.insert(next).inserted { pending.append(next) }
            }
        }
        return reached == ids
    }
}

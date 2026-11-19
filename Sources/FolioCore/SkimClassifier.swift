import Foundation
import CoreML
import NaturalLanguage

public enum SkimFacet: String, CaseIterable, Sendable, Identifiable {
    case objective, method, result
    public var id: String { rawValue }
    public var label: String { self == .objective ? "Goal" : self == .method ? "Method" : "Result" }
}

public struct SkimSentence: Sendable, Equatable {
    public let page: Int
    public let location: Int
    public let length: Int
    public let paragraph: Int
    public let text: String
    public init(page: Int, location: Int, length: Int, paragraph: Int, text: String) {
        self.page = page; self.location = location; self.length = length; self.paragraph = paragraph; self.text = text
    }
}

public struct SkimPrediction: Sendable {
    public let sentence: SkimSentence
    public let facet: SkimFacet
    public let score: Double
    public init(sentence: SkimSentence, facet: SkimFacet, score: Double) {
        self.sentence = sentence; self.facet = facet; self.score = score
    }
}

/// The same uncased WordPiece contract as the adapted MiniLM training/export pipeline.
public struct SkimTokenizer: Sendable {
    private let vocabulary: [String: Int]
    public init(vocabulary: String) {
        self.vocabulary = Dictionary(vocabulary.components(separatedBy: .newlines).enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }
    public func encode(_ text: String) -> [Int] {
        var words: [String] = [], current = ""
        func flush() { if !current.isEmpty { words.append(current); current = "" } }
        let normalized = text.lowercased().decomposedStringWithCanonicalMapping
        for scalar in normalized.unicodeScalars {
            let value = scalar.value, category = scalar.properties.generalCategory
            if category == .nonspacingMark { continue }
            if scalar.properties.isWhitespace { flush(); continue }
            if category == .control || category == .format || value == 0xFFFD { continue }
            let punctuation = (33...47).contains(value) || (58...64).contains(value) || (91...96).contains(value) || (123...126).contains(value)
                || CharacterSet.punctuationCharacters.contains(scalar)
            let cjk = (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || (0x20000...0x2FA1F).contains(value)
            if punctuation || cjk { flush(); words.append(String(scalar)) }
            else { current.unicodeScalars.append(scalar) }
        }
        flush()
        var ids: [Int] = []
        for word in words {
            if ids.count >= 80 { break }
            let chars = Array(word)
            guard chars.count <= 100 else { ids.append(100); continue }
            var start = 0, pieces: [Int] = [], unknown = false
            while start < chars.count {
                var end = chars.count, found: Int?
                while end > start {
                    if let id = vocabulary[(start == 0 ? "" : "##") + String(chars[start..<end])] { found = id; break }
                    end -= 1
                }
                guard let found else { unknown = true; break }
                pieces.append(found); start = end
            }
            ids.append(contentsOf: unknown ? [100] : pieces)
        }
        return Array(ids.prefix(80))
    }

    public struct Window: Sendable {
        public let ids: [Int]
        public let targets: [(sentence: Int, position: Int)]
    }
    /// Consecutive sentences retain context across paragraph boundaries; up to three are replayed.
    public static func windows(_ encoded: [[Int]]) -> [Window] {
        var result: [Window] = [], next = 0
        while next < encoded.count {
            var first = max(0, next - 3)
            while first < next && (1 + encoded[first...next].reduce(0) { $0 + $1.count + 1 }) > 512 { first += 1 }
            var ids = [101], targets: [(Int, Int)] = []
            var index = first
            while index < encoded.count && index - first < 10 {
                let piece = Array(encoded[index].prefix(80))
                if ids.count + piece.count + 1 > 512 { break }
                ids.append(contentsOf: piece); ids.append(102)
                if index >= next { targets.append((index, ids.count - 1)) }
                index += 1
            }
            result.append(Window(ids: ids, targets: targets))
            next = targets.last!.0 + 1
        }
        return result
    }
}

/// Native, local inference. Actor isolation keeps loading/prediction off the UI actor.
public actor SkimClassifier {
    public static let shared = SkimClassifier()
    private var loaded: (MLModel, SkimTokenizer)?
    private let directory: URL
    public static var modelDirectory: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Skim", isDirectory: true)
        if let bundled, FileManager.default.fileExists(atPath: bundled.appendingPathComponent("manifest.json").path) { return bundled }
        // SwiftPM commands run from the repository; never compile the builder's source path into the app.
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Models/Skim", isDirectory: true)
    }
    public init(directory: URL = SkimClassifier.modelDirectory) { self.directory = directory }
    /// Ranges remain relative to the original PDFKit page string, including line breaks/hyphens.
    public nonisolated static func sentences(in pages: [String]) -> [SkimSentence] {
        var result: [SkimSentence] = [], paragraph = 0
        for (index, text) in pages.enumerated() {
            // PDF soft wraps are not sentence boundaries. Replace only single newlines,
            // preserving UTF-16 length so ranges still address the original PDFKit string.
            let normalized = text.replacingOccurrences(of: "(?<!\n)\n(?!\n)", with: " ", options: .regularExpression)
            let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = normalized
            var previousEnd = text.startIndex, count = 0
            tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { tokenRange, _ in
                let ns = NSRange(tokenRange, in: normalized)
                guard let range = Range(ns, in: text) else { return true }
                let original = String(text[range])
                let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
                let gap = text[previousEnd..<range.lowerBound]
                if gap.contains("\n\n") || count >= 3 { paragraph += 1; count = 0 }
                previousEnd = range.upperBound
                // Ignore headings, tiny fragments and equation/table-like lines, without section label bans.
                guard trimmed.count >= 25, trimmed.split(whereSeparator: \.isWhitespace).count >= 5 else { return true }
                result.append(.init(page: index + 1, location: ns.location, length: ns.length, paragraph: paragraph,
                                    text: original.replacingOccurrences(of: "-\n", with: "").replacingOccurrences(of: "\n", with: " ")))
                count += 1
                return true
            }
            paragraph += 1
        }
        return result
    }
    public func classifyPages(_ pages: [String]) throws -> [SkimPrediction] {
        try classify(Self.sentences(in: pages))
    }
    public enum Failure: LocalizedError {
        case missingModel, invalidModel
        public var errorDescription: String? {
            switch self {
            case .missingModel: "The adapted Skim model is missing. Rebuild Folio with its local Skim model resources."
            case .invalidModel: "The Skim model returned an invalid classification."
            }
        }
    }
    public func classify(_ sentences: [SkimSentence]) throws -> [SkimPrediction] {
        try Task.checkCancellation()
        guard !sentences.isEmpty else { return [] }
        if loaded == nil {
            let url = directory.appendingPathComponent("AdaptedMiniLM.mlmodelc")
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.missingModel }
            struct Manifest: Decodable { let model: String; let labels: [String] }
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
            guard manifest.model == "scim-adapted", manifest.labels == ["background", "method", "objective", "other", "result"] else { throw Failure.invalidModel }
            let configuration = MLModelConfiguration(); configuration.computeUnits = .cpuAndGPU
            let model = try MLModel(contentsOf: url, configuration: configuration)
            let tokenizer = try SkimTokenizer(vocabulary: String(contentsOf: directory.appendingPathComponent("vocab.txt"), encoding: .utf8))
            loaded = (model, tokenizer)
        }
        let (model, tokenizer) = loaded!
        let windows = SkimTokenizer.windows(sentences.map { tokenizer.encode($0.text) })
        let labels = ["background", "method", "objective", "other", "result"]
        var predictions: [SkimPrediction] = []
        for window in windows {
            try Task.checkCancellation()
            let ids = try MLMultiArray(shape: [1, 512], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, 512], dataType: .int32)
            for position in 0..<512 {
                ids[position] = NSNumber(value: position < window.ids.count ? window.ids[position] : 0)
                mask[position] = NSNumber(value: position < window.ids.count ? 1 : 0)
            }
            let input = try MLDictionaryFeatureProvider(dictionary: ["input_ids": MLFeatureValue(multiArray: ids), "attention_mask": MLFeatureValue(multiArray: mask)])
            guard let logits = try model.prediction(from: input).featureValue(for: "logits")?.multiArrayValue,
                  logits.shape.map(\.intValue) == [1, 512, 5] else { throw Failure.invalidModel }
            for target in window.targets {
                let row = (0..<5).map { logits[[0, NSNumber(value: target.position), NSNumber(value: $0)]].doubleValue }
                guard row.allSatisfy(\.isFinite), let maximum = row.max(), let best = row.firstIndex(of: maximum) else { throw Failure.invalidModel }
                let score = 1 / row.reduce(0) { $0 + exp($1 - maximum) }
                if let facet = SkimFacet(rawValue: labels[best]) {
                    predictions.append(SkimPrediction(sentence: sentences[target.sentence], facet: facet, score: score))
                }
            }
        }
        return Self.pickHighlights(predictions)
    }
    /// One confident sentence per paragraph. Scores are model probabilities, not calibrated certainty.
    public nonisolated static func pickHighlights(_ predictions: [SkimPrediction], minimumScore: Double = 0.5) -> [SkimPrediction] {
        var best: [Int: SkimPrediction] = [:]
        for prediction in predictions where prediction.score.isFinite && prediction.score >= minimumScore {
            if prediction.score > (best[prediction.sentence.paragraph]?.score ?? -.infinity) { best[prediction.sentence.paragraph] = prediction }
        }
        return best.values.sorted { ($0.sentence.page, $0.sentence.location) < ($1.sentence.page, $1.sentence.location) }
    }
}

import XCTest
@testable import FolioCore

final class SkimClassifierTests: XCTestCase {
    func testWordPieceNormalizationAndUnknownWords() {
        let tokenizer = SkimTokenizer(vocabulary: "[PAD]\n[UNK]\nhello\nworld\n,\nun\n##seen\n中\n")
        XCTAssertEqual(tokenizer.encode("Héllo, WORLD unseen 中 missing"), [2, 4, 3, 5, 6, 7, 100])
        XCTAssertEqual(tokenizer.encode(String(repeating: "hello ", count: 100)).count, 80)
    }

    func testWindowsCoverEverySentenceExactlyOnceAtSeparatorAndWithinBounds() {
        let encoded = (0..<37).map { Array(repeating: $0 + 1000, count: $0 % 2 == 0 ? 80 : 12) }
        let windows = SkimTokenizer.windows(encoded)
        XCTAssertEqual(windows.flatMap { $0.targets.map(\.sentence) }, Array(encoded.indices))
        XCTAssertTrue(windows.allSatisfy { $0.ids.count <= 512 && $0.ids.first == 101 })
        for window in windows {
            for target in window.targets {
                XCTAssertEqual(window.ids[target.position], 102)
                XCTAssertEqual(Array(window.ids[(target.position - encoded[target.sentence].count)..<target.position]), encoded[target.sentence])
            }
        }
        XCTAssertTrue(SkimTokenizer.windows([]).isEmpty)
    }

    func testSentenceRangesKeepUnicodeAndOriginalPDFOffsets() {
        let page = "Heading\nWe investigate β-models and evaluate their behavior.\nOur method uses a compact en-\ncoder to classify sentences.\n\nThe results show an improvement over prior approaches."
        let sentences = SkimClassifier.sentences(in: [page, "", "We compare several scientific classifiers on held-out examples."])
        XCTAssertFalse(sentences.isEmpty)
        for sentence in sentences where sentence.page == 1 {
            let original = (page as NSString).substring(with: NSRange(location: sentence.location, length: sentence.length))
            XCTAssertEqual(sentence.text, original.replacingOccurrences(of: "-\n", with: "").replacingOccurrences(of: "\n", with: " "))
        }
        XCTAssertEqual(sentences.last?.page, 3)
        XCTAssertGreaterThan(sentences.last!.paragraph, sentences.first!.paragraph)
        XCTAssertTrue(SkimClassifier.sentences(in: ["", "Abstract\n123"]).isEmpty)
    }

    func testDensityThresholdRetainsRolesWithoutForcingEqualCounts() {
        let sentences = (0..<4).map { SkimSentence(page: 1, location: $0 * 30, length: 25, paragraph: $0 / 2, text: "Synthetic scientific sentence.") }
        let candidates = [SkimPrediction(sentence: sentences[0], facet: .objective, score: 0.6),
                          SkimPrediction(sentence: sentences[1], facet: .method, score: 0.8),
                          SkimPrediction(sentence: sentences[2], facet: .result, score: 0.49),
                          SkimPrediction(sentence: sentences[3], facet: .result, score: .nan)]
        XCTAssertEqual(SkimClassifier.pickHighlights(candidates).map(\.facet), [.method])
    }

    func testWrappedPDFLinesRemainOneSentenceWithOriginalOffsets() throws {
        let text = "We investigate compact scientific classifiers\nusing several held-out datasets and compare\ntheir performance against a larger baseline."
        let sentences = SkimClassifier.sentences(in: [text])
        XCTAssertEqual(sentences.count, 1)
        let sentence = try XCTUnwrap(sentences.first)
        XCTAssertEqual(sentence.text, text.replacingOccurrences(of: "\n", with: " "))
        XCTAssertEqual(sentence.location, 0)
        XCTAssertEqual(sentence.length, text.utf16.count)
    }

    func testMissingModelFailsWithoutFallback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let classifier = SkimClassifier(directory: directory)
        do {
            _ = try await classifier.classify([.init(page: 1, location: 0, length: 30, paragraph: 0, text: "We evaluate a compact scientific classifier.")])
            XCTFail("Missing model must fail")
        } catch { XCTAssertTrue(error is SkimClassifier.Failure) }
    }

    func testNativeAdaptedModelMatchesExportedTokenizerAndPredictions() async throws {
        struct Manifest: Decodable {
            struct Check: Decodable {
                let sentences: [String]
                let token_ids: [[Int]]
                let labels: [Int]
                let scores: [Double]
            }
            let verification: [Check]
        }
        let directory = SkimClassifier.modelDirectory
        try XCTSkipUnless(FileManager.default.fileExists(atPath: directory.appendingPathComponent("AdaptedMiniLM.mlmodelc").path),
                          "Adapted Skim weights are not tracked; export the model to run native prediction parity.")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        let tokenizer = try SkimTokenizer(vocabulary: String(contentsOf: directory.appendingPathComponent("vocab.txt")))
        let classifier = SkimClassifier(directory: directory)
        let labels = ["background", "method", "objective", "other", "result"]
        for check in manifest.verification {
            XCTAssertEqual(check.sentences.map(tokenizer.encode), check.token_ids)
            let sentences = check.sentences.enumerated().map { SkimSentence(page: 1, location: $0.offset * 100, length: $0.element.utf16.count, paragraph: $0.offset, text: $0.element) }
            let actual = try await classifier.classify(sentences)
            let expected = check.labels.indices.filter { SkimFacet(rawValue: labels[check.labels[$0]]) != nil && check.scores[$0] >= 0.5 }
            XCTAssertEqual(actual.map(\.sentence.location), expected.map { $0 * 100 })
            XCTAssertEqual(actual.map(\.facet.rawValue), expected.map { labels[check.labels[$0]] })
            for prediction in actual {
                XCTAssertEqual(prediction.score, check.scores[prediction.sentence.paragraph], accuracy: 0.01)
            }
        }
    }
}

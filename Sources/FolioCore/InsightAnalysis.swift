import Foundation

/// Local, extractive paper insights: no model and no network. Everything derives from the PDF's own text layer,
/// so a key sentence is always a sentence the paper actually contains.
public struct InsightSentence: Equatable, Identifiable {
    public var id: String { "\(page):\(text.prefix(40))" }
    public let text: String
    public let page: Int
}
public struct InsightKeyword: Equatable, Identifiable { public var id: String { term }; public let term: String; public let count: Int }
public struct PaperInsights: Equatable {
    public let words: Int
    public let minutes: Int
    public let abstract: String
    public let keySentences: [InsightSentence]
    public let keywords: [InsightKeyword]
}

public enum InsightAnalysis {
    private static let stop: Set<String> = Set("a about above after again against all also am an and any are as at be because been before being below between both but by can could did do does doing down during each few for from further had has have having he her here his how however i if in into is it its just more most my no nor not now of off on once only or other our out over own same she should so some such than that the their them then there these they this those through to too under until up very was we were what when where which while who whom why will with would you your et al fig figure table section paper study studies using used use based may might within one two three first second thus therefore although whether among across per via upon either each every many much several new shown show shows found result results data".split(separator: " ").map(String.init))

    public static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !($0.isLetter || $0 == "'" || $0 == "-") }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'-")) }.filter { $0.count > 1 && $0.first!.isLetter }
    }
    private static func content(_ word: String) -> Bool { word.count > 2 && !stop.contains(word) }
    public static func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"(\w)-\s+(\w)"#, with: "$1$2", options: .regularExpression).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Sentences of plausible prose length; layout noise (running headers, shouted captions, number runs) is dropped.
    public static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let characters = Array(text); var i = 0
        while i < characters.count {
            current.append(characters[i])
            if ".!?".contains(characters[i]), i + 2 < characters.count, characters[i + 1] == " ", characters[i + 2].isUppercase || "(“\"".contains(characters[i + 2]) {
                out.append(current); current = ""; i += 1   // skip the separating space
            }
            i += 1
        }
        if !current.isEmpty { out.append(current) }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { sentence in
            guard (40...420).contains(sentence.count) else { return false }
            let digits = sentence.filter(\.isNumber).count
            let upper = sentence.filter(\.isUppercase).count, lower = sentence.filter(\.isLowercase).count
            return Double(digits) < Double(sentence.count) * 0.15 && Double(upper) <= Double(lower) * 0.5 && !sentence.contains("@")
        }
    }

    public static func keywords(_ text: String, limit: Int = 8) -> [InsightKeyword] {
        let list = words(text); var freq: [String: Int] = [:], pairs: [String: Int] = [:]
        for (index, word) in list.enumerated() where content(word) {
            freq[word, default: 0] += 1
            if index + 1 < list.count, content(list[index + 1]) { pairs[word + " " + list[index + 1], default: 0] += 1 }
        }
        var picked: [InsightKeyword] = []
        for (term, count) in pairs.filter({ $0.value >= 3 }).sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) where picked.count < 4 {
            let parts = Set(term.split(separator: " ").map(String.init))
            if !picked.contains(where: { !Set($0.term.split(separator: " ").map(String.init)).isDisjoint(with: parts) }) { picked.append(InsightKeyword(term: term, count: count)) }
        }
        for (term, count) in freq.filter({ $0.value >= 2 }).sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) where picked.count < limit {
            if !picked.contains(where: { $0.term.split(separator: " ").contains(Substring(term)) }) { picked.append(InsightKeyword(term: term, count: count)) }
        }
        return picked
    }

    public static func abstract(_ text: String) -> String {
        guard let head = text.prefix(20_000).range(of: #"(?<![A-Za-z])[Aa] ?[Bb] ?[Ss] ?[Tt] ?[Rr] ?[Aa] ?[Cc] ?[Tt][\s.:—–-]*(?=[A-Z0-9“"(])"#, options: .regularExpression) else { return "" }
        let rest = String(text[head.upperBound...].prefix(2600))
        // Preserve line boundaries until section detection; flattening first can swallow the paper body.
        let section = rest.range(of: #"(?m)^\s*(?:\d{1,2}(?:\.\d{1,2})*\.?|[IVX]{1,5}\.)[ \t]+[A-Z][^\n]{0,100}(?:\n|$)"#, options: .regularExpression)
        let end = rest.range(of: #"(?<![A-Za-z])(?:\d{1,2}\.?\s+)?(?:I ?[Nn] ?[Tt] ?[Rr] ?[Oo] ?[Dd] ?[Uu] ?[Cc] ?[Tt] ?[Ii] ?[Oo] ?[Nn]|Keywords|Key words|Index Terms|CCS Concepts)(?![a-z])"#, options: .regularExpression)
        let stop = [end?.lowerBound, section?.lowerBound].compactMap { $0 }.min()
        var body = stop.map { String(rest[..<$0]) } ?? String(rest.prefix(1800))
        body = clean(body)
        if let cut = body.lastIndex(of: "."), body.distance(from: body.startIndex, to: cut) > 60 { body = String(body[...cut]) }
        return body.count >= 100 && body.filter(\.isLowercase).count * 100 > body.count * 55 ? body : ""
    }

    public static func analyze(pages: [String], limit: Int = 6) -> PaperInsights {
        let cleaned = pages.map(clean)
        let full = cleaned.joined(separator: " ")
        let count = words(full).count
        let abstract = abstract(pages.prefix(2).joined(separator: "\n\n"))
        let body = abstract.isEmpty ? full : full.replacingOccurrences(of: abstract, with: " ")
        var frequency: [String: Int] = [:]
        for word in words(body) where content(word) { frequency[word, default: 0] += 1 }
        let top = Double(max(1, frequency.values.max() ?? 1))
        var all: [InsightSentence] = []
        for (pageIndex, page) in cleaned.enumerated() {
            for sentence in sentences(page) { all.append(InsightSentence(text: sentence, page: pageIndex + 1)) }
        }
        var scored: [(Int, Double)] = []
        for (index, item) in all.enumerated() {
            if !abstract.isEmpty && abstract.contains(item.text) { continue }
            let ws = words(item.text).filter(content)
            guard ws.count >= 5 else { continue }
            let weight = ws.reduce(0.0) { $0 + Double(frequency[$1] ?? 0) / top } / Double(ws.count).squareRoot()
            let position = Double(index) / Double(max(1, all.count))
            let bonus = position < 0.15 ? 1.25 : position > 0.85 ? 1.15 : 1.0
            let cue = item.text.range(of: #"\b(we (find|show|propose|present|examine|measure|conclude)|results? (show|suggest|indicate)|in conclusion|this (paper|study))\b"#, options: [.regularExpression, .caseInsensitive]) != nil ? 1.3 : 1.0
            scored.append((index, weight * bonus * cue))
        }
        var seen = Set<String>(); var chosen: [Int] = []
        for (index, _) in scored.sorted(by: { $0.1 > $1.1 }) where chosen.count < limit {
            if seen.insert(String(all[index].text.prefix(60)).lowercased()).inserted { chosen.append(index) }
        }
        return PaperInsights(words: count, minutes: max(1, Int((Double(count) / 230).rounded())), abstract: abstract, keySentences: chosen.sorted().map { all[$0] }, keywords: keywords(full))
    }
}

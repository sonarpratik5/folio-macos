import Foundation

public enum AssistantBlock: Equatable {
    case paragraph(String)
    case heading(Int, String)
    case bullets([String])
    case numbered([String])
    case quote(String)
    case code(language: String?, text: String)
    case math(String)
}

/// Lightweight, dependency-free structure for assistant answers: Markdown blocks, LaTeX-to-Unicode, citation links.
public enum AssistantRichText {
    public static let pageScheme = "folio-page"

    public static func blocks(_ source: String) -> [AssistantBlock] {
        var result: [AssistantBlock] = []
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0
        var paragraph: [String] = []
        func flush() { if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] } }
        while index < lines.count {
            let line = lines[index]; let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []; index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[index]); index += 1 }
                result.append(.code(language: language.isEmpty ? nil : language, text: code.joined(separator: "\n"))); index += 1; continue
            }
            if trimmed.hasPrefix("$$") || trimmed.hasPrefix("\\[") {
                flush()
                let closing = trimmed.hasPrefix("$$") ? "$$" : "\\]"
                var body = String(trimmed.dropFirst(2))
                if let end = body.range(of: closing) { body = String(body[..<end.lowerBound]) }
                else {
                    index += 1
                    while index < lines.count {
                        let next = lines[index]
                        if let end = next.range(of: closing) { body += "\n" + next[..<end.lowerBound]; break }
                        body += "\n" + next; index += 1
                    }
                }
                result.append(.math(body.trimmingCharacters(in: .whitespacesAndNewlines))); index += 1; continue
            }
            if trimmed.isEmpty { flush(); index += 1; continue }
            if let heading = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flush(); let level = trimmed[heading].filter { $0 == "#" }.count
                result.append(.heading(level, String(trimmed[heading.upperBound...]))); index += 1; continue
            }
            if trimmed.hasPrefix(">") {
                flush(); var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); index += 1
                }
                result.append(.quote(quote.joined(separator: " "))); continue
            }
            if trimmed.range(of: #"^[-*•]\s+"#, options: .regularExpression) != nil {
                flush(); var items: [String] = []
                while index < lines.count, let marker = lines[index].trimmingCharacters(in: .whitespaces).range(of: #"^[-*•]\s+"#, options: .regularExpression) {
                    let text = lines[index].trimmingCharacters(in: .whitespaces); items.append(String(text[marker.upperBound...])); index += 1
                }
                result.append(.bullets(items)); continue
            }
            if trimmed.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) != nil {
                flush(); var items: [String] = []
                while index < lines.count, let marker = lines[index].trimmingCharacters(in: .whitespaces).range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) {
                    let text = lines[index].trimmingCharacters(in: .whitespaces); items.append(String(text[marker.upperBound...])); index += 1
                }
                result.append(.numbered(items)); continue
            }
            paragraph.append(trimmed); index += 1
        }
        flush()
        return result
    }

    /// Markdown for one inline run: inline LaTeX becomes readable Unicode and page citations become links.
    public static func inlineMarkdown(_ text: String, pageCount: Int? = nil) -> String {
        var segments: [(String, Bool)] = []   // (text, isCode)
        var rest = text[...]
        while let start = rest.firstIndex(of: "`") {
            segments.append((String(rest[..<start]), false))
            let after = rest.index(after: start)
            if let end = rest[after...].firstIndex(of: "`") { segments.append((String(rest[start...end]), true)); rest = rest[rest.index(after: end)...] }
            else { segments.append((String(rest[start...]), false)); rest = ""[...] }
        }
        segments.append((String(rest), false))
        return segments.map { segment, isCode in isCode ? segment : citations(math(segment), pageCount: pageCount) }.joined()
    }

    static func math(_ text: String) -> String {
        var out = text
        for pattern in [#"\$\$(.+?)\$\$"#, #"(?<![\\$\d])\$(?=\S)([^$\n]+?)(?<=\S)\$(?!\d)"#, #"\\\((.+?)\\\)"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = out as NSString; var rebuilt = ""; var last = 0
            for match in regex.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                rebuilt += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                rebuilt += escape(latex(ns.substring(with: match.range(at: 1))))
                last = match.range.location + match.range.length
            }
            rebuilt += ns.substring(from: last); out = rebuilt
        }
        return out
    }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "_", with: "\\_").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "`", with: "\\`")
    }
    static func citations(_ text: String, pageCount: Int?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\bp{1,2}\.\s*(\d{1,5})(?:\s*[–−-]\s*(\d{1,5}))?"#) else { return text }
        let ns = text as NSString; var out = ""; var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let page = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let before = match.range.location >= 1 ? ns.substring(with: NSRange(location: match.range.location - 1, length: 1)) : ""
            guard page >= 1, page <= (pageCount ?? .max), before != "[" else { continue }
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out += "[\(ns.substring(with: match.range))](\(pageScheme)://\(page))"
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }
    public static func page(from url: URL) -> Int? { url.scheme == pageScheme ? Int(url.host ?? "") : nil }

    // MARK: LaTeX to Unicode

    private static let symbols: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "times": "×", "cdot": "·", "pm": "±", "mp": "∓", "div": "÷", "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "approx": "≈", "sim": "∼", "simeq": "≃", "equiv": "≡", "propto": "∝",
        "infty": "∞", "partial": "∂", "nabla": "∇", "sum": "∑", "prod": "∏", "int": "∫", "oint": "∮", "sqrt": "√", "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "cup": "∪", "cap": "∩",
        "forall": "∀", "exists": "∃", "emptyset": "∅", "to": "→", "rightarrow": "→", "leftarrow": "←", "leftrightarrow": "↔", "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔", "mapsto": "↦",
        "ldots": "…", "cdots": "⋯", "dots": "…", "langle": "⟨", "rangle": "⟩", "ell": "ℓ", "hbar": "ℏ", "otimes": "⊗", "oplus": "⊕", "circ": "∘", "bullet": "•", "top": "⊤", "perp": "⊥", "neg": "¬", "land": "∧", "lor": "∨",
        "log": "log", "ln": "ln", "exp": "exp", "sin": "sin", "cos": "cos", "tan": "tan", "min": "min", "max": "max", "arg": "arg", "lim": "lim", "softmax": "softmax", "mathbb": "", "quad": " ", "qquad": "  ", "ast": "∗"
    ]
    private static let supers: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "T": "ᵀ"]
    private static let subs: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "n": "ₙ", "m": "ₘ", "t": "ₜ", "x": "ₓ"]

    public static func latex(_ source: String) -> String {
        var text = source
        for command in ["left", "right", "displaystyle", "big", "Big", "bigg"] { text = text.replacingOccurrences(of: "\\\(command)", with: "") }
        text = text.replacingOccurrences(of: "\\,", with: " ").replacingOccurrences(of: "\\;", with: " ").replacingOccurrences(of: "\\!", with: "").replacingOccurrences(of: "\\ ", with: " ")
        // Wrapper commands keep their argument.
        text = replace(#"\\(?:text|mathrm|mathbf|mathit|mathcal|mathbb|boldsymbol|operatorname|textbf|mathsf|vec|hat|bar|tilde)\s*\{([^{}]*)\}"#, in: text) { $0[1] }
        for _ in 0..<4 {
            text = replace(#"\\d?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}"#, in: text) { "\(wrap($0[1]))⁄\(wrap($0[2]))" }
            text = replace(#"\\sqrt\s*\{([^{}]*)\}"#, in: text) { "√(\($0[1]))" }
        }
        text = replace(#"\\([A-Za-z]+)"#, in: text) { symbols[$0[1]] ?? $0[1] }
        text = replace(#"\^\s*\{([^{}]*)\}"#, in: text) { script($0[1], table: supers, mark: "^") }
        text = replace(#"\^\s*([A-Za-z0-9+\-])"#, in: text) { script($0[1], table: supers, mark: "^") }
        text = replace(#"_\s*\{([^{}]*)\}"#, in: text) { script($0[1], table: subs, mark: "_") }
        text = replace(#"_\s*([A-Za-z0-9])"#, in: text) { script($0[1], table: subs, mark: "_") }
        text = text.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "").replacingOccurrences(of: "\\", with: "")
        return text.split(whereSeparator: { $0 == "\n" }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
    private static func wrap(_ value: String) -> String { value.count <= 1 || value.allSatisfy({ $0.isLetter || $0.isNumber }) ? value : "(\(value))" }
    private static func script(_ value: String, table: [Character: Character], mark: String) -> String {
        let converted = value.map { table[$0] }
        return converted.allSatisfy({ $0 != nil }) ? String(converted.compactMap { $0 }) : (value.count == 1 ? "\(mark)\(value)" : "\(mark)(\(value))")
    }
    private static func replace(_ pattern: String, in text: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString; var out = ""; var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out += transform((0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) })
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }
}

import Foundation

/// arXiv link parsing, mirroring the web app's arxiv-id.mjs.
public enum ArxivID {
    private static let modern = try! NSRegularExpression(pattern: #"^(\d{4}\.\d{4,5})(v\d+)?$"#)
    private static let legacy = try! NSRegularExpression(pattern: #"^([a-z-]+(?:\.[A-Z]{2})?/\d{7})(v\d+)?$"#)

    private static func bare(_ s: String) -> String? {
        let range = NSRange(s.startIndex..., in: s)
        for regex in [modern, legacy] where regex.firstMatch(in: s, range: range) != nil { return s }
        return nil
    }

    /// The arXiv id (with version, if given) for a link or id, or nil.
    public static func parse(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 300 else { return nil }
        if let r = s.range(of: #"^arxiv:\s*"#, options: [.regularExpression, .caseInsensitive]) { s.removeSubrange(r) }
        if let direct = bare(s) { return direct }
        let withScheme = s.range(of: #"^[A-Za-z]+://"#, options: .regularExpression) != nil ? s : "https://" + s
        guard let url = URLComponents(string: withScheme), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host?.lowercased(),
              ["arxiv.org", "www.arxiv.org", "export.arxiv.org"].contains(host) else { return nil }
        let path = url.percentEncodedPath
        guard let r = path.range(of: #"^/(?:abs|pdf|html)/(.+?)(?:\.pdf)?/?$"#, options: .regularExpression) else { return nil }
        var tail = String(path[r])
        for prefix in ["/abs/", "/pdf/", "/html/"] where tail.hasPrefix(prefix) { tail.removeFirst(prefix.count); break }
        if tail.hasSuffix("/") { tail.removeLast() }
        if tail.lowercased().hasSuffix(".pdf") { tail.removeLast(4) }
        guard let decoded = tail.removingPercentEncoding else { return nil }
        return bare(decoded)
    }

    public static func pdfURL(for id: String) -> URL? { URL(string: "https://arxiv.org/pdf/\(id)") }
    public static func apiURL(for id: String) -> URL? { URL(string: "https://export.arxiv.org/api/query?id_list=\(id)") }

    /// First entry title of an Atom API response, unescaped.
    public static func atomTitle(_ xml: String) -> String {
        guard let entry = xml.range(of: #"<entry>[\s\S]*?</entry>"#, options: .regularExpression),
              let t = String(xml[entry]).range(of: #"(?<=<title>)[\s\S]*?(?=</title>)"#, options: .regularExpression) else { return "" }
        return String(String(xml[entry])[t])
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func fileName(id: String, title: String?) -> String {
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        let collapsed = (title ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let clean = String(String.UnicodeScalarView(collapsed.unicodeScalars.filter { !forbidden.contains($0) }))
            .trimmingCharacters(in: .whitespaces)
        let tag = id.replacingOccurrences(of: "/", with: "_")
        let trimmed = String(clean.prefix(140)).trimmingCharacters(in: .whitespaces)
        return (trimmed.isEmpty ? "arXiv \(tag)" : "\(trimmed) (arXiv \(tag))") + ".pdf"
    }
}

/// Downloads an arXiv PDF to a temporary file. Network happens only when `download` is called from a user action.
public struct ArxivDownloader {
    public enum DownloadError: LocalizedError {
        case notPDF, http(Int), tooLarge
        public var errorDescription: String? {
            switch self {
            case .notPDF: "arXiv did not return a PDF for that paper."
            case .http(let code): "arXiv responded with status \(code)."
            case .tooLarge: "That file is larger than Folio will download (200 MB)."
            }
        }
    }
    public static let maximumBytes = 200 * 1024 * 1024

    public init() {}

    /// True when the data begins with the PDF magic number (allowing leading whitespace).
    public static func looksLikePDF(_ prefix: Data) -> Bool {
        prefix.prefix(1024).range(of: Data("%PDF-".utf8)) != nil
    }

    /// Returns (temporary file, paper title if the API answered). Cancel by cancelling the surrounding Task.
    public func download(id: String, session: URLSession = .shared,
                         progress: @Sendable @escaping (Double?) -> Void = { _ in }) async throws -> (file: URL, title: String?) {
        guard let pdf = ArxivID.pdfURL(for: id) else { throw DownloadError.notPDF }
        var title: String?
        if let api = ArxivID.apiURL(for: id), let (data, response) = try? await session.data(from: api),
           (response as? HTTPURLResponse)?.statusCode == 200, let xml = String(data: data, encoding: .utf8) {
            let found = ArxivID.atomTitle(xml)
            title = found.isEmpty ? nil : found
        }
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(from: pdf)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw DownloadError.http(http.statusCode) }
        let expected = response.expectedContentLength
        if expected > Int64(Self.maximumBytes) { throw DownloadError.tooLarge }
        var data = Data()
        var count = 0
        for try await byte in bytes {
            data.append(byte)
            count += 1
            if count & 0xFFFF == 0 {
                try Task.checkCancellation()
                if count > Self.maximumBytes { throw DownloadError.tooLarge }
                progress(expected > 0 ? Double(count) / Double(expected) : nil)
            }
        }
        guard Self.looksLikePDF(data) else { throw DownloadError.notPDF }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("folio-arxiv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(ArxivID.fileName(id: id, title: title))
        try data.write(to: file)
        return (file, title)
    }
}

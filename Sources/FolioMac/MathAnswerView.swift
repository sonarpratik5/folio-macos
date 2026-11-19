import SwiftUI
import WebKit
import FolioCore

/// WebKit is confined to offline equation typography; the reader and app remain native PDFKit/SwiftUI.
struct MathAnswerView: View {
    let text: String
    let pageCount: Int?
    let onPage: (Int) -> Void
    @State private var height: CGFloat = 80
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        EquationWebView(text: text, pageCount: pageCount, dark: scheme == .dark, height: $height, onPage: onPage)
            .frame(height: height)
    }
}

@MainActor
private struct EquationWebView: NSViewRepresentable {
    let text: String
    let pageCount: Int?
    let dark: Bool
    @Binding var height: CGFloat
    let onPage: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "size")
        if let url = Bundle.module.url(forResource: "katex.min", withExtension: "js", subdirectory: "Math"), let js = try? String(contentsOf: url) {
            configuration.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        let html = MathAnswerHTML.document(text, pageCount: pageCount, dark: dark)
        guard html != context.coordinator.lastHTML else { return }
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName: "size"); view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: EquationWebView
        var lastHTML = ""
        init(_ parent: EquationWebView) { self.parent = parent }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? Double, value.isFinite, value > 0 else { return }
            let height = min(100_000, ceil(value))
            if abs(parent.height - height) > 1 { parent.height = height }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("""
            document.querySelectorAll('[data-tex]').forEach(el => {
                try { katex.render(el.getAttribute('data-tex'), el, {displayMode: el.tagName === 'DIV', throwOnError: false, trust: false, strict: 'ignore', maxExpand: 1000, maxSize: 20}); } catch (_) {}
            });
            function measure() { window.webkit.messageHandlers.size.postMessage(document.body.scrollHeight); }
            new ResizeObserver(measure).observe(document.body); document.fonts.ready.then(measure); measure();
            """, completionHandler: nil)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel); return
            }
            if let page = AssistantRichText.page(from: url) { parent.onPage(page) }
            else if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
}

/// Escapes untrusted answer text before generating markup; no remote resources or answer-provided HTML execute.
enum MathAnswerHTML {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    private static let style: String = {
        guard let folder = Bundle.module.url(forResource: "Math", withExtension: nil),
              var css = try? String(contentsOf: folder.appendingPathComponent("katex.min.css")) else { return "" }
        // Inline fonts: zero file access or network access is required by the equation surface.
        let regex = try! NSRegularExpression(pattern: #"url\((fonts/[^)]+)\)"#)
        for match in regex.matches(in: css, range: NSRange(css.startIndex..., in: css)).reversed() {
            let ns = css as NSString
            let path = ns.substring(with: match.range(at: 1))
            let data = (try? Data(contentsOf: folder.appendingPathComponent(path))) ?? Data()
            let mime = path.hasSuffix("woff2") ? "font/woff2" : path.hasSuffix("woff") ? "font/woff" : "font/ttf"
            css = (css as NSString).replacingCharacters(in: match.range, with: "url(data:\(mime);base64,\(data.base64EncodedString()))")
        }
        return css
    }()
    static func inline(_ source: String, pageCount: Int?) -> String {
        // Tokenize code and math together, so dollar signs inside code never become equations.
        let regex = try! NSRegularExpression(pattern: #"`([^`]+)`|\$\$([\s\S]+?)\$\$|(?<![\\$\d])\$(?=\S)([^$\n]+?)(?<=\S)\$(?!\d)|\\\(([\s\S]+?)\\\)|\[([^\]\n]+)\]\((https?://[^\s)]+)\)"#)
        let ns = source as NSString; var result = ""; var last = 0
        func prose(_ value: String) -> String {
            var html = escape(value)
            for (pattern, template) in [(#"\*\*(.+?)\*\*"#, "<strong>$1</strong>"), (#"\*(.+?)\*"#, "<em>$1</em>")] {
                html = html.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
            }
            let citations = try! NSRegularExpression(pattern: #"\bp{1,2}\.\s*(\d{1,5})"#)
            for match in citations.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
                let value = html as NSString
                if let n = Int(value.substring(with: match.range(at: 1))), n > 0, n <= (pageCount ?? .max) {
                    html = value.replacingCharacters(in: match.range, with: "<a href='folio-page://\(n)'>\(value.substring(with: match.range))</a>")
                }
            }
            return html
        }
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            result += prose(ns.substring(with: NSRange(location: last, length: match.range.location - last)))
            if match.range(at: 1).location != NSNotFound { result += "<code>\(escape(ns.substring(with: match.range(at: 1))))</code>" }
            else if match.range(at: 5).location != NSNotFound {
                let label = escape(ns.substring(with: match.range(at: 5)))
                let url = escape(ns.substring(with: match.range(at: 6)))
                result += "<a href='\(url)'>\(label)</a>"
            }
            else if let range = (2..<5).map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }) {
                let tex = escape(ns.substring(with: range)); result += "<span data-tex='\(tex)'>\(tex)</span>"
            }
            last = match.range.location + match.range.length
        }
        return result + prose(ns.substring(from: last))
    }
    static func document(_ source: String, pageCount: Int?, dark: Bool) -> String {
        let body = AssistantRichText.blocks(source).map { block -> String in
            switch block {
            case .paragraph(let text): return "<p>\(inline(text, pageCount: pageCount))</p>"
            case .heading(let level, let text): return "<h\(level)>\(inline(text, pageCount: pageCount))</h\(level)>"
            case .quote(let text): return "<blockquote>\(inline(text, pageCount: pageCount))</blockquote>"
            case .code(_, let text): return "<pre><code>\(escape(text))</code></pre>"
            case .bullets(let items): return "<ul>" + items.map { "<li>\(inline($0, pageCount: pageCount))</li>" }.joined() + "</ul>"
            case .numbered(let items): return "<ol>" + items.map { "<li>\(inline($0, pageCount: pageCount))</li>" }.joined() + "</ol>"
            case .math(let text): return "<div data-tex='\(escape(text))'>\(escape(text))</div>"
            }
        }.joined()
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; font-src data:; script-src 'none'"><style>\(style)
        html { color-scheme: \(dark ? "dark" : "light"); } body { margin:0; padding:0 0 4px; color:\(dark ? "#ededed" : "#242424"); font:13px -apple-system; overflow-wrap:anywhere; line-height:1.5; } p { margin:0 0 10px; } a { color:#4095ef; } pre,.katex-display { overflow-x:auto; } pre { padding:10px; background:#8882; } blockquote { margin-left:0; padding-left:12px; border-left:3px solid #4095ef; } .katex { font-size:1.15em; } </style></head><body>\(body)</body></html>
        """
    }
}

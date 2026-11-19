import SwiftUI
import AppKit
import FolioCore

/// Native Markdown for plain answers; offline typesetting for answers containing inline/display LaTeX.
struct AssistantRichView: View {
    let text: String
    var pageCount: Int? = nil
    var onPage: (Int) -> Void = { _ in }

    var body: some View {
        Group {
            if text.contains("$") || text.contains("\\[") || text.contains("\\(") {
                MathAnswerView(text: text, pageCount: pageCount, onPage: onPage)
            } else { nativeBody }
        }
    }

    private var nativeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(AssistantRichText.blocks(text).enumerated()), id: \.offset) { _, block in blockView(block) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if let page = AssistantRichText.page(from: url) { onPage(page); return .handled }
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
        })
    }

    private func inline(_ source: String) -> Text {
        let markdown = AssistantRichText.inlineMarkdown(source, pageCount: pageCount)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var attributed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(source)
        for run in attributed.runs where run.link != nil { attributed[run.range].foregroundColor = NSColor(FolioTheme.accent); attributed[run.range].underlineStyle = .single }
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true { attributed[run.range].font = .system(.callout, design: .monospaced) }
        return Text(attributed)
    }

    @ViewBuilder private func blockView(_ block: AssistantBlock) -> some View {
        switch block {
        case .paragraph(let value): inline(value).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let value):
            inline(value).font(level <= 1 ? FolioTheme.heading(21) : level == 2 ? FolioTheme.heading(18) : .headline).padding(.top, 4)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•").foregroundStyle(FolioTheme.accent); inline(item).fixedSize(horizontal: false, vertical: true) }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary); inline(item).fixedSize(horizontal: false, vertical: true) }
                }
            }
        case .quote(let value):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(FolioTheme.accent.opacity(0.5)).frame(width: 3)
                inline(value).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(language ?? "code").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Copy code").accessibilityLabel("Copy code")
                }.padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
                ScrollView(.horizontal) { Text(code).font(.system(.callout, design: .monospaced)).padding(12).fixedSize() }
            }
            .background(FolioTheme.background, in: RoundedRectangle(cornerRadius: FolioRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FolioRadius.control, style: .continuous).strokeBorder(FolioTheme.line))
        case .math(let value):
            Text(AssistantRichText.latex(value)).font(.system(size: 17, design: .serif).italic())
                .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 14)
                .background(FolioTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: FolioRadius.control, style: .continuous))
                .accessibilityLabel("Equation: \(AssistantRichText.latex(value))")
        }
    }
}

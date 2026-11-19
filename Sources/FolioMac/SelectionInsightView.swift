import SwiftUI
import PDFKit
import FolioCore

struct SelectionInsightRequest: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let page: Int
    var bounds: CGRect = .zero
}

@MainActor
final class SelectionInsightModel: ObservableObject {
    @Published var answer = ""
    @Published var error: String?
    @Published var busy = false
    private struct CacheKey: Equatable {
        let fingerprint: String
        let provider: AssistantProvider
        let model: String
        let text: String
        let page: Int
    }
    // Ephemeral and bounded: reopening a completed selection does not spend another request.
    private static var cache: [(key: CacheKey, answer: String)] = []
    private let service: AssistantService
    init(service: AssistantService = AssistantService()) { self.service = service }

    static func question(for text: String) -> String {
        let term = text.split(whereSeparator: { $0.isWhitespace }).count <= 4
        return term
            ? "Explain the selected term as used here in under 80 words. Use **In plain words:** for a simple definition, **In this paper:** for its role with a PDF page citation, and optionally **Think of it as:** for an accurate everyday analogy. Use short sentences and no preamble."
            : "Explain the selected passage in under 110 words. Use **In plain words:** to restate it simply, **Why it matters:** for its role in this paper with PDF page citations, and optionally **Terms:** for up to two technical definitions. Use short sentences and no preamble."
    }

    func explain(_ request: SelectionInsightRequest, root: URL?, record: PaperRecord, provider: AssistantProvider, refresh: Bool = false) async {
        do {
            let paper = try PaperAssistantModel.readPaper(root: root, record: record)
            try Task.checkCancellation()
            await explain(request, paper: paper, provider: provider, refresh: refresh)
        } catch is CancellationError { }
        catch { answer = ""; busy = false; self.error = error.localizedDescription }
    }

    func explain(_ request: SelectionInsightRequest, paper: AssistantPaper, provider: AssistantProvider, refresh: Bool = false) async {
        let key = CacheKey(fingerprint: paper.fingerprint, provider: provider,
                           model: provider == .claude ? UserDefaults.standard.string(forKey: ClaudeKeyStore.modelDefaultsKey) ?? "claude-sonnet-5-5" : "gpt-6.1-terra",
                           text: request.text, page: request.page)
        if !refresh, let hit = Self.cache.first(where: { $0.key == key }) {
            answer = hit.answer; error = nil; busy = false; return
        }
        busy = true; error = nil; answer = ""
        defer { busy = false }
        do {
            let response = try await service.answer(
                question: Self.question(for: request.text),
                paper: paper, history: [], provider: provider, page: request.page,
                selection: request.text, simplified: true)
            try Task.checkCancellation()
            guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AssistantError.message("No insight came back. Try again.")
            }
            answer = response
            Self.cache.removeAll { $0.key == key }
            Self.cache.append((key, response))
            if Self.cache.count > 24 { Self.cache.removeFirst() }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

/// Hosted in a native transient popover beside the selected PDF text.
struct SelectionInsightPopup: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ObservedObject var workspace: Workspace
    let request: SelectionInsightRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(FolioTheme.accent)
                Text(request.text.split(whereSeparator: { $0.isWhitespace }).count <= 4 ? "Term insight" : "Passage insight")
                    .font(.headline)
                Spacer()
                Text("p. \(request.page)").font(.caption).foregroundStyle(.secondary)
                Button { workspace.selectionInsight = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close insight (Esc)").accessibilityLabel("Close insight")
            }
            ProviderSwitch()
            SelectionInsightResult(workspace: workspace, request: request).id(request.id)
        }
        .padding(16).frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            if reduceTransparency || contrast == .increased {
                FolioTheme.panelRight
            } else {
                Rectangle().fill(.thinMaterial)
            }
        }
        .onExitCommand { workspace.selectionInsight = nil }
    }
}

/// Measure natural content at the popup width; only overflow receives a scroll viewport.
struct InsightScrollBody<Content: View>: View {
    @State private var contentHeight: CGFloat = 32
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: InsightBodyHeight.self, value: geometry.size.height)
                })
        }
        .frame(height: min(260, contentHeight))
        .onPreferenceChange(InsightBodyHeight.self) { height in
            let rounded = max(1, ceil(height))
            if abs(contentHeight - rounded) > 0.5 { contentHeight = rounded }
        }
    }
}

private struct InsightBodyHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct SelectionInsightResult: View {
    @ObservedObject var workspace: Workspace
    let request: SelectionInsightRequest
    @StateObject private var model = SelectionInsightModel()
    @State private var attempt = 0
    @AppStorage("folio.assistant.provider") private var providerValue = AssistantProvider.codex.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.text).font(.callout).lineLimit(5).textSelection(.enabled).folioWell(padding: 10)
            InsightScrollBody {
                VStack(alignment: .leading, spacing: 12) {
                    if model.busy {
                        HStack { ProgressView().controlSize(.small); Text("Explaining selection…") }
                        Button("Stop") { workspace.selectionInsight = nil }
                    } else if let error = model.error {
                        Text(error).foregroundStyle(FolioTheme.warning).textSelection(.enabled)
                        Button("Try again") { attempt += 1 }
                    } else {
                        AssistantRichView(text: model.answer, pageCount: workspace.document?.pageCount, onPage: { workspace.go(to: $0) })
                        HStack {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(model.answer, forType: .string)
                            }
                            Spacer()
                            Button("Ask more") {
                                workspace.insightsMode = false; workspace.selectionInsight = nil
                                workspace.present(.assistant, selection: request.text, page: request.page,
                                                  prompt: "Help me understand this passage further.")
                            }.buttonStyle(.link)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: attempt) {
            guard let record = workspace.activePaper else { return }
            await model.explain(request, root: workspace.repository?.root, record: record,
                                provider: AssistantProvider(rawValue: providerValue) ?? .codex, refresh: attempt > 0)
        }
        .onChange(of: providerValue) { _, _ in workspace.selectionInsight = nil }
    }
}

extension Workspace {
    func chooseInsightsMode() {
        let enabled = !insightsMode
        guard finishEditorIfNeeded() else { return }
        chooseTool(.select)
        insightsMode = enabled
        selectionInsight = nil
        pdfView?.window?.makeFirstResponder(pdfView)
    }

    /// Called once at the end of a PDF selection gesture; passive selection never sends.
    func explainFinishedSelection() {
        guard insightsMode, tool == .select, reading,
              let selection = pdfView?.currentSelection,
              let raw = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let firstPage = selection.pages.first, let index = document?.index(for: firstPage), index != NSNotFound else { return }
        let text = String(raw.prefix(12_000)), page = index + 1
        guard selectionInsight?.text != text || selectionInsight?.page != page else { return }
        let line = selection.selectionsByLine().first ?? selection
        selectionInsight = SelectionInsightRequest(text: text, page: page, bounds: line.bounds(for: firstPage))
    }
}

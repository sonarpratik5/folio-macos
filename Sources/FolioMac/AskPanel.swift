import SwiftUI
import PDFKit
import FolioCore

/// The reader's inline AI chat (web "Ask" sidebar section). Lives beside the PDF; the selected passage attaches
/// automatically, suggestions and Explain send in one click, and nothing is sent without an explicit reader action.
struct AskPanel: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var model: PaperAssistantModel
    let paper: PaperRecord
    @AppStorage("folio.assistant.provider") private var providerValue = AssistantProvider.codex.rawValue
    @AppStorage("folio.assistant.simplified") private var simplified = false
    @State private var question = ""
    @State private var liveSelection = ""
    @State private var attached: (text: String, page: Int)?
    @State private var detached = false
    @State private var renaming: AssistantThread?
    @State private var renameText = ""
    @State private var deleting: AssistantThread?
    @FocusState private var composerFocused: Bool
    @State private var claudeReady = true

    private var provider: AssistantProvider { AssistantProvider(rawValue: providerValue) ?? .codex }
    private var ready: Bool { model.paper != nil && !model.busy }
    /// Passage that the next question carries: an explicit request first, else the live PDF selection.
    private var passage: (text: String, page: Int)? {
        if detached { return nil }
        if let attached { return attached }
        let text = liveSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : (String(text.prefix(12_000)), workspace.page)
    }
    private static let explainPrompt = "Explain this selected passage in plain language, including its role in the paper."
    private static let suggestions: [(String, String)] = [
        ("Summarize the main contribution", "text.redaction"),
        ("Explain what this page is about", "doc.text.magnifyingglass"),
        ("What evidence supports the key claim?", "checkmark.seal"),
        ("What are the limitations?", "exclamationmark.bubble")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 10)
            FolioHairline()
            messages
            if let error = model.error { errorBanner(error) }
            else if let attempt = model.retry, !model.busy { stoppedBanner(attempt) }
            FolioHairline()
            composer.padding(12).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FolioTheme.panelRight)
        .onAppear { model.load(root: workspace.repository?.root, record: paper); liveSelection = currentSelection }
        .onChange(of: workspace.askRequest, initial: true) { _, request in consume(request) }
        .onChange(of: providerValue, initial: true) { _, _ in claudeReady = ClaudeKeyStore.isReady }
        .onReceive(NotificationCenter.default.publisher(for: ClaudeKeyStore.changed)) { _ in claudeReady = ClaudeKeyStore.isReady }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewSelectionChanged)) { note in
            guard (note.object as AnyObject?) === workspace.pdfView else { return }
            liveSelection = currentSelection
            if !liveSelection.isEmpty { attached = nil; detached = false }
        }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Rename") { if let id = renaming?.id { model.rename(id, to: renameText) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Chat", role: .destructive) { if let id = deleting?.id { model.delete(id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This removes the conversation from this Mac. It cannot be undone.") }
    }

    private var currentSelection: String {
        workspace.pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: Header
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProviderSwitch()
                Spacer(minLength: 0)
                Button { workspace.inspector = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(ReaderIconStyle(size: 26)).help("Close panel").accessibilityLabel("Close panel")
            }
            HStack(spacing: 4) {
                Text("Ask").font(FolioTheme.heading(22)).foregroundStyle(FolioTheme.panelTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                chatsMenu
                Button { model.newThread(); composerFocused = true } label: { Image(systemName: "square.and.pencil") }
                    .help("New chat").accessibilityLabel("New chat").disabled(!ready)
                optionsMenu
            }.buttonStyle(ReaderIconStyle(size: 26))
            if let thread = model.threads?.active, !thread.turns.isEmpty {
                Text(thread.title).font(.caption).foregroundStyle(FolioTheme.muted).lineLimit(1)
            }
        }
    }
    private var chatsMenu: some View {
        Menu {
            let threads = model.threads?.threads ?? []
            if threads.isEmpty { Text("No saved chats yet") }
            ForEach(threads) { thread in
                Button { model.select(thread.id) } label: {
                    if thread.id == model.threads?.activeID { Label(thread.title, systemImage: "checkmark") } else { Text(thread.title) }
                }
            }
            if let thread = model.threads?.active {
                Divider()
                Button("Rename Chat…") { renameText = thread.title; renaming = thread }
                Button("Delete Chat…", role: .destructive) { deleting = thread }
            }
        } label: { Image(systemName: "clock.arrow.circlepath") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 26, height: 26)
            .help("Chat history").accessibilityLabel("Chat history").disabled(model.busy)
    }
    private var optionsMenu: some View {
        Menu {
            Toggle("Simple Technical English", isOn: $simplified)
        } label: { Image(systemName: "slider.horizontal.3") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 26, height: 26)
            .help("Answer style").accessibilityLabel("AI options").disabled(model.busy)
    }

    // MARK: Messages
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.activeTurns.isEmpty && model.pendingQuestion == nil { emptyState }
                    ForEach(model.activeTurns) { turn in bubble(turn) }
                    if let pending = model.pendingQuestion {
                        userBubble(pending, passage: nil)
                        VStack(alignment: .leading, spacing: 6) {
                            if model.streaming.isEmpty {
                                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.progress).font(.callout).foregroundStyle(FolioTheme.muted) }
                            } else {
                                AssistantRichView(text: model.streaming, pageCount: paper.pageCount, onPage: openPage)
                                    .font(.system(size: 14)).lineSpacing(3)
                            }
                        }.id("streaming")
                    }
                    Color.clear.frame(height: 1).id("end")
                }.padding(16)
            }
            .onAppear { if !model.activeTurns.isEmpty { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: model.activeTurns.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: model.streaming) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.pendingQuestion) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.threads?.activeID) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about this paper").font(.system(size: 17, weight: .regular, design: .serif)).foregroundStyle(FolioTheme.panelTitle)
            if provider == .claude && !claudeReady {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "key").foregroundStyle(FolioTheme.warning)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Claude API key unavailable. Check the configured environment or choose Codex CLI.").font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(FolioTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text("Select text in the PDF to ask about a passage. Answers cite pages you can click.")
                .font(.callout).foregroundStyle(FolioTheme.muted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.suggestions, id: \.0) { item in
                    Button { submit(item.0, passage: nil) } label: {
                        Label(item.0, systemImage: item.1).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(FolioTheme.ink)
                        .background(FolioTheme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .disabled(!ready)
                }
            }.padding(.top, 4)
            Text("Sending shares extracted paper text with \(provider.name). Chats stay on this Mac.")
                .font(.caption).foregroundStyle(FolioTheme.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
        }
    }
    @ViewBuilder private func bubble(_ turn: AssistantTurn) -> some View {
        if turn.role == .user {
            let parts = AskPanel.split(turn.content)
            userBubble(parts.question, passage: parts.passage)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                AssistantRichView(text: turn.content, pageCount: paper.pageCount, onPage: openPage)
                    .font(.system(size: 14)).lineSpacing(3)
                HStack {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(turn.content, forType: .string) } label: {
                        Label("Copy", systemImage: "doc.on.doc").font(.caption).padding(.horizontal, 6).frame(height: 28)
                    }
                    .buttonStyle(.plain).foregroundStyle(FolioTheme.muted)
                    .help("Copy answer").accessibilityLabel("Copy answer")
                    Spacer(minLength: 0)
                }
            }.id(turn.id)
        }
    }
    private func userBubble(_ text: String, passage: String?) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let passage {
                Text(passage).font(.caption).foregroundStyle(FolioTheme.muted).lineLimit(3).padding(7)
                    .overlay(alignment: .leading) { Rectangle().fill(FolioTheme.accent.opacity(0.5)).frame(width: 2) }
                    .background(FolioTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Text(text).font(.system(size: 14)).textSelection(.enabled).padding(.horizontal, 12).padding(.vertical, 9)
                .background(FolioTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }.frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 28)
    }
    /// Stored user turns carry their passage inline; show it as a quote above the question.
    static func split(_ content: String) -> (passage: String?, question: String) {
        let content = content.replacingOccurrences(of: #"^\[Reading page [0-9]+ of [0-9]+\]\n"#, with: "", options: .regularExpression)
        guard content.hasPrefix("Selected passage (p."), let range = content.range(of: "\n\n", options: .backwards), let colon = content.firstIndex(of: "\n") else { return (nil, content) }
        let head = String(content[..<colon]).replacingOccurrences(of: "Selected passage ", with: "").dropLast()
        let passage = String(content[content.index(after: colon)..<range.lowerBound])
        return ("\(head) “\(passage)”", String(content[range.upperBound...]))
    }
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(FolioTheme.warning)
            Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 4) {
                Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(ReaderIconStyle(size: 22)).accessibilityLabel("Dismiss error")
                if let attempt = model.retry { Button("Retry") { send(attempt) }.controlSize(.small).disabled(model.busy) }
            }
        }.padding(10).background(FolioTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12).padding(.bottom, 8)
    }
    private func stoppedBanner(_ attempt: AssistantAttempt) -> some View {
        HStack {
            Image(systemName: "stop.circle").foregroundStyle(FolioTheme.muted)
            Text("Stopped before an answer was saved.").font(.callout).foregroundStyle(FolioTheme.muted)
            Spacer()
            Button("Retry") { send(attempt) }.controlSize(.small)
        }.padding(.horizontal, 16).padding(.bottom, 8)
    }

    // MARK: Composer
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let passage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.quote").foregroundStyle(FolioTheme.accent).font(.caption)
                    Text("p. \(passage.page) · \(passage.text)").font(.caption).foregroundStyle(FolioTheme.muted).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { detached = true; attached = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(FolioTheme.muted).help("Don’t attach this passage").accessibilityLabel("Remove attached passage")
                }
                .padding(8).background(FolioTheme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Button { submit(Self.explainPrompt, passage: passage) } label: { Label("Explain this passage", systemImage: "sparkles") }
                    .controlSize(.small).disabled(!ready)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Question", text: $question,
                          prompt: Text(passage == nil ? "Ask about this paper…" : "Ask about the passage…").foregroundStyle(FolioTheme.muted), axis: .vertical)
                    .lineLimit(3...6).textFieldStyle(.plain).focused($composerFocused)
                    .font(.system(size: 14)).foregroundStyle(FolioTheme.ink)
                    .padding(.leading, 12).padding(.vertical, 12)
                    .accessibilityLabel("Question about this paper")
                    .onSubmit(sendTyped).disabled(model.paper == nil)
                if model.busy {
                    Button { model.cancel() } label: {
                        Image(systemName: "stop.fill").font(.system(size: 12, weight: .semibold)).frame(width: 32, height: 32)
                            .foregroundStyle(FolioTheme.onAccent).background(FolioTheme.accent, in: Circle())
                    }
                        .buttonStyle(.plain).foregroundStyle(FolioTheme.accent).keyboardShortcut(".", modifiers: [.command])
                        .help("Stop (⌘.)").accessibilityLabel("Stop answer")
                        .padding(.trailing, 6).padding(.vertical, 6)
                } else {
                    Button(action: sendTyped) {
                        Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).frame(width: 32, height: 32)
                            .foregroundStyle(canSend ? FolioTheme.onAccent : FolioTheme.muted)
                            .background(canSend ? FolioTheme.accent : FolioTheme.line, in: Circle())
                    }
                        .buttonStyle(.plain)
                        .disabled(!canSend).help("Send (Return)").accessibilityLabel("Send question")
                        .padding(.trailing, 6).padding(.vertical, 6)
                }
            }
            .background(FolioTheme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(composerFocused ? FolioTheme.accent : FolioTheme.fieldLine, lineWidth: 1)
            }
        }
    }
    private var canSend: Bool { ready && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Actions
    private func sendTyped() {
        guard canSend else { return }
        submit(question, passage: passage); question = ""
    }
    private func submit(_ text: String, passage: (text: String, page: Int)?) {
        send(AssistantAttempt(question: text, selection: passage?.text, page: min(max(passage?.page ?? workspace.page, 1), paper.pageCount), simplified: simplified))
        attached = nil
    }
    private func send(_ attempt: AssistantAttempt) {
        model.ask(attempt.question, provider: provider, page: attempt.page, selection: attempt.selection, simplified: attempt.simplified)
    }
    private func consume(_ request: AskRequest?) {
        guard let request else { return }
        workspace.askRequest = nil
        model.load(root: workspace.repository?.root, record: paper)
        detached = false
        if let text = request.selection { attached = (String(text.prefix(12_000)), request.page) }
        if request.autoSend, model.paper != nil, !model.busy, !request.prompt.isEmpty {
            submit(request.prompt, passage: attached)
        } else {
            if !request.prompt.isEmpty { question = request.prompt }
            composerFocused = true
        }
    }
    private func openPage(_ page: Int) { workspace.go(to: page) }
}

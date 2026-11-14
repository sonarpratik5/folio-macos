import SwiftUI
import FolioCore

/// Sections of the reader's right panel: Notes, Ask, Reviews and Map. Overview lives on Insights,
/// so AI tools open beside the PDF instead of in separate windows.
enum ReaderPanel: String, CaseIterable, Identifiable {
    case notes, ask, reviews, map
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notes: "Notes"
        case .ask: "Ask AI"
        case .reviews: "Peer reviews"
        case .map: "Concept map"
        }
    }
    var symbol: String {
        switch self {
        case .notes: "note.text"
        case .ask: "sparkles"
        case .reviews: "text.bubble"
        case .map: "point.3.connected.trianglepath.dotted"
        }
    }
    var shortcutHint: String? {
        switch self {
        case .ask: "⌘J"
        case .reviews: "⌥⌘R"
        case .map: "⌥⌘M"
        case .notes: nil
        }
    }
}

/// A one-shot request for the Ask panel: prefill and optionally send. Created only by explicit reader actions.
struct AskRequest: Equatable {
    let id = UUID()
    var selection: String?
    var page: Int
    var prompt: String
    var autoSend: Bool
}

/// AI state for the open paper. Lives on the Workspace so switching panel sections never cancels a running request.
@MainActor
final class PaperAIStore: ObservableObject {
    let paperID: UUID
    let assistant = PaperAssistantModel()
    let reviews = PaperReviewsModel()
    let concepts = PaperConceptGraphModel()
    init(paperID: UUID) { self.paperID = paperID }
    func cancelAll() { assistant.cancel(); reviews.cancel(); concepts.cancel() }
}

/// Shared header for every right-panel section: small eyebrow, serif title, trailing controls and a close button.
struct PanelHeader<Trailing: View>: View {
    @ObservedObject var workspace: Workspace
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if eyebrow == "Folio AI" { ProviderSwitch() }
                else { Text(eyebrow.uppercased()).font(.system(size: 12)).tracking(1.7).foregroundStyle(FolioTheme.eyebrow) }
                Spacer()
                trailing()
                Button { workspace.inspector = false } label: { Image(systemName: "xmark") }
                    .help("Close panel").accessibilityLabel("Close panel")
            }.buttonStyle(ReaderIconStyle(size: 26))
            Text(title).font(.system(size: 24, weight: .regular, design: .serif)).foregroundStyle(FolioTheme.panelTitle)
                .accessibilityAddTraits(.isHeader)
        }
    }
}
extension PanelHeader where Trailing == EmptyView {
    init(workspace: Workspace, eyebrow: String, title: String) {
        self.init(workspace: workspace, eyebrow: eyebrow, title: title, trailing: { EmptyView() })
    }
}

/// Always-visible 44pt icon rail at the reader's right edge. Clicking an icon opens that section;
/// clicking the open section again collapses the panel (web rail behaviour).
struct ReaderPanelRail: View {
    @ObservedObject var workspace: Workspace
    var body: some View {
        VStack(spacing: 6) {
            ForEach(ReaderPanel.allCases) { section in
                let active = workspace.inspector && workspace.panel == section
                Button { workspace.toggle(section) } label: { Image(systemName: section.symbol) }
                    .buttonStyle(ReaderIconStyle(active: active))
                    .help(section.label + (section.shortcutHint.map { " (\($0))" } ?? ""))
                    .accessibilityLabel(section.label)
                    .accessibilityAddTraits(active ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.top, 12).frame(width: 44).frame(maxHeight: .infinity)
        .background(FolioTheme.strip)
    }
}

extension Workspace {
    /// The AI store for the active paper; nil until `ensureAIStore()` runs for it.
    var activeAIStore: PaperAIStore? { aiStore?.paperID == activeID && activeID != nil ? aiStore : nil }
    /// Creates the store for the active paper, cancelling and replacing another paper's store. Call outside view updates.
    @discardableResult func ensureAIStore() -> PaperAIStore? {
        if let store = activeAIStore { return store }
        aiStore?.cancelAll(); aiStore = nil
        guard let id = activeID else { return nil }
        let store = PaperAIStore(paperID: id); aiStore = store
        return store
    }
    func toggle(_ section: ReaderPanel) {
        if inspector && panel == section { inspector = false } else { panel = section; inspector = true }
    }
}

/// One-click Codex CLI ⇄ Claude API switch shown in every AI panel header. The choice is shared by all AI features.
struct ProviderSwitch: View {
    @AppStorage("folio.assistant.provider") private var providerValue = AssistantProvider.codex.rawValue
    @AppStorage(ClaudeKeyStore.modelDefaultsKey) private var claudeModel = "claude-sonnet-5-5"
    @State private var claudeReady = true
    private var provider: AssistantProvider { AssistantProvider(rawValue: providerValue) ?? .codex }
    var body: some View {
        Menu {
            Picker("AI provider", selection: $providerValue) {
                Text("Codex CLI · GPT-6.1 Terra").tag(AssistantProvider.codex.rawValue)
                Text("Claude API · \(ClaudeKeyStore.models.first { $0.id == claudeModel }?.name.components(separatedBy: " · ").first ?? claudeModel)").tag(AssistantProvider.claude.rawValue)
            }.pickerStyle(.inline)
            if provider == .claude && !claudeReady {
                Divider()
                Text("No Claude API key yet")
            }
            Divider()
            SettingsLink { Text(provider == .claude && !claudeReady ? "Add Claude API Key…" : "AI Settings…") }
        } label: {
            HStack(spacing: 4) {
                Text("FOLIO AI · \(provider == .claude ? "CLAUDE" : "CODEX")").font(.system(size: 12)).tracking(1.7)
                if provider == .claude && !claudeReady { Image(systemName: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(FolioTheme.warning) }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }.foregroundStyle(FolioTheme.eyebrow).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Switch AI provider (Codex CLI or Claude API)").accessibilityLabel("AI provider: \(provider.name)")
        .onAppear(perform: refresh)
        .onChange(of: providerValue) { _, _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ClaudeKeyStore.changed)) { _ in refresh() }
    }
    private func refresh() { claudeReady = ClaudeKeyStore.isReady }
}

extension ClaudeKeyStore {
    static let changed = Notification.Name("dev.folio.mac.claudeKeyChanged")
    /// A Claude key is available from the launch environment or the Keychain.
    static var isReady: Bool {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || hasKey
    }
}

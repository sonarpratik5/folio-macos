import SwiftUI
import FolioCore

struct AISettingsView: View {
    @AppStorage("folio.assistant.provider") private var provider = AssistantProvider.codex.rawValue
    @AppStorage(ClaudeKeyStore.modelDefaultsKey) private var claudeModel = "claude-sonnet-5-5"
    @State private var keyDraft = ""
    @State private var hasStoredKey = false
    @State private var keyStatus: String?
    private let environmentKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    private let environmentModel = ProcessInfo.processInfo.environment["FOLIO_ASSISTANT_MODEL"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FolioHeader("Reading assistant", size: 23)
            Picker("Provider", selection: $provider) {
                ForEach(AssistantProvider.allCases) { item in Text(item.name).tag(item.rawValue) }
            }.pickerStyle(.segmented)
            Text("Used by Ask, Explain, At a glance, Peer reviews and Concept map. You can also switch from the header of any AI panel.")
                .foregroundStyle(.secondary)
            if provider == AssistantProvider.codex.rawValue {
                FolioChip(title: "GPT-6.1 Terra · medium reasoning", symbol: "terminal", selected: true)
                Text("Install Codex CLI and run codex login in a terminal. Folio uses your existing CLI sign-in. If needed, set FOLIO_CODEX_CLI in Folio’s launch environment to the executable’s full path.")
            } else {
                claudeSection
            }
            Text("Each Send, Explain or Generate sends extracted paper text to the selected provider. Chat can use bounded paper lookups and web search. Requests start only when you press a button; Stop cancels the active request. There is no automatic provider fallback.")
                .foregroundStyle(.secondary)
            Text("Conversation history and source-backed overviews are saved locally beside this library’s managed PDFs. Paper text and provider responses are treated as untrusted content.")
                .foregroundStyle(.secondary)
        }
        .font(.callout).padding(24).frame(maxWidth: 600, alignment: .leading).folioSheetBackground()
        .onAppear { hasStoredKey = ClaudeKeyStore.hasKey }
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Model", selection: $claudeModel) {
                ForEach(ClaudeKeyStore.models, id: \.id) { Text($0.name).tag($0.id) }
            }.disabled(environmentModel != nil)
            if let environmentModel { Text("FOLIO_ASSISTANT_MODEL overrides this: \(environmentModel)").font(.caption).foregroundStyle(.secondary) }

            VStack(alignment: .leading, spacing: 6) {
                Text("Claude API key").font(.headline)
                HStack {
                    SecureField("Claude API key", text: $keyDraft, prompt: Text(hasStoredKey ? "Saved in Keychain — paste to replace" : "Paste your sk-ant-… key"))
                        .labelsHidden().textFieldStyle(.roundedBorder).onSubmit(saveKey)
                    Button("Save", action: saveKey).disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasStoredKey { Button("Remove", role: .destructive, action: removeKey) }
                }
                Label(statusText, systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(ready ? FolioTheme.accent : FolioTheme.warning)
                Text("The key is stored only in this Mac’s Keychain and sent only to api.anthropic.com with Claude requests. It is never shown again or saved in the library.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var ready: Bool { environmentKey || hasStoredKey }
    private var statusText: String {
        if let keyStatus { return keyStatus }
        if environmentKey { return "Using ANTHROPIC_API_KEY from Folio’s launch environment." }
        return hasStoredKey ? "Key saved in Keychain." : "Add a key to use Claude API."
    }
    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if ClaudeKeyStore.save(key) {
            keyDraft = ""; hasStoredKey = true; keyStatus = "Key saved in Keychain. Claude API is ready."
            NotificationCenter.default.post(name: ClaudeKeyStore.changed, object: nil)
        } else { keyStatus = "macOS blocked saving the key. Unlock your login Keychain in Keychain Access, then save again. Folio will not ask for its password." }
    }
    private func removeKey() {
        guard ClaudeKeyStore.delete() else {
            keyStatus = "The Keychain could not remove the key. Your saved key was kept."
            return
        }
        hasStoredKey = false; keyStatus = nil
        NotificationCenter.default.post(name: ClaudeKeyStore.changed, object: nil)
    }
}

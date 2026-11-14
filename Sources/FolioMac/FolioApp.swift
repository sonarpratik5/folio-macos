import SwiftUI
import FolioCore

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = Workspace()
    @AppStorage("appearance") private var appearance = "system"

    init() {
        // One-time, human-run key import: `FolioMac --import-claude-key-from <path/to/.env>`.
        // Saves ANTHROPIC_API_KEY to this Mac's Keychain (owned by Folio) and exits without opening a window or printing the key.
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--import-claude-key-from"), flag + 1 < args.count {
            let text = (try? String(contentsOfFile: args[flag + 1], encoding: .utf8)) ?? ""
            guard let key = ClaudeKeyStore.key(fromDotEnv: text) else { print("No ANTHROPIC_API_KEY found."); exit(2) }
            print(ClaudeKeyStore.save(key) ? "Claude API key saved to the Keychain." : "The Keychain did not accept the key.")
            exit(ClaudeKeyStore.hasKey ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup("Folio", id: "main") {
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { appDelegate.workspace = workspace; QAHarness.startIfRequested(workspace) }
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
        .defaultSize(width: 1380, height: 880)
        .commands {
            ReaderCommands(workspace: workspace)
            CommandGroup(replacing: .newItem) {
                Button("Import PDF…", action: workspace.choosePDF).keyboardShortcut("o")
                Button("Import from arXiv…") { workspace.showArxivImport = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Export PDF Copy…", action: workspace.exportCopy)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(workspace.document == nil || !workspace.reading)
                Divider()
                Button("Add Writing Page After This Page") { workspace.insertWritingPage(after: workspace.page) }
                    .keyboardShortcut("n", modifiers: [.command, .option]).disabled(workspace.document == nil || !workspace.reading)
                Button("Add Writing Page at End") { workspace.insertWritingPage(after: nil) }
                    .disabled(workspace.document == nil || !workspace.reading)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo", action: workspace.undo).keyboardShortcut("z")
                Button("Redo", action: workspace.redo).keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("Assistant") {
                Button("Ask About This Paper…") { workspace.present(.assistant) }.keyboardShortcut("j", modifiers: [.command])
                    .disabled(workspace.activePaper == nil)
                Button("Ask About Selection…") { workspace.askAboutSelection(explain: false) }.keyboardShortcut("a", modifiers: [.command, .option])
                    .disabled(workspace.activePaper == nil)
                Button("Explain Selection") { workspace.askAboutSelection(explain: true) }.keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(workspace.activePaper == nil)
                Divider()
                Button("Paper at a Glance") { workspace.present(.overview) }.keyboardShortcut("g", modifiers: [.command, .option])
                    .disabled(workspace.activePaper == nil)
                Button("Peer Reviews") { workspace.present(.reviews) }.keyboardShortcut("r", modifiers: [.command, .option])
                    .disabled(workspace.activePaper == nil)
                Button("Concept Map") { workspace.present(.concepts) }.keyboardShortcut("m", modifiers: [.command, .option])
                    .disabled(workspace.activePaper == nil)
            }
        }
        Settings { SettingsView().frame(width: 590, height: 640) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var workspace: Workspace? {
        didSet { if let workspace, !pendingFiles.isEmpty { workspace.importPDFs(pendingFiles); pendingFiles = [] } }
    }
    @MainActor private var pendingFiles: [URL] = []

    /// Finder "Open With", dock-icon drops and `open -a`. Files are imported as managed copies.
    @MainActor func application(_ application: NSApplication, open urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else { return }
        if let workspace { workspace.importPDFs(pdfs) } else { pendingFiles += pdfs }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        workspace?.finishEditorIfNeeded() == false ? .terminateCancel : .terminateNow
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

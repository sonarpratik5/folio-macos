import SwiftUI
import FolioCore

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = Workspace()
    @AppStorage("appearance") private var appearance = "system"

    init() {
        ClaudeKeyStore.prepareNonInteractiveAccess()
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
                .modifier(FolioWindowLifecycle(appDelegate: appDelegate, workspace: workspace))
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1380, height: 880)
        .commands {
            ReaderCommands(workspace: workspace)
            CommandGroup(replacing: .newItem) {
                Button("Open folder…", action: workspace.chooseFolder).keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Import PDF…", action: workspace.choosePDF).keyboardShortcut("o")
                Button("Import from arXiv…") { workspace.showArxivImport = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Export PDF Copy…") { workspace.exportCopy() }
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
                Button("Insights on Selection") { workspace.chooseInsightsMode() }
                    .disabled(workspace.activePaper == nil || !workspace.reading)
                Button(workspace.skimEnabled ? "Turn Skim Highlights Off" : "Turn Skim Highlights On") { workspace.toggleSkim() }
                    .disabled(workspace.activePaper == nil || !workspace.reading)
                Button("Explain Selection") { workspace.askAboutSelection(explain: true) }.keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(workspace.activePaper == nil)
                Divider()
                Button("Paper at a Glance") { workspace.present(.overview) }.keyboardShortcut("g", modifiers: [.command, .option, .shift])
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
    @MainActor weak var mainWindow: NSWindow?
    @MainActor private var menuBar: MenuBarController?

    @MainActor func installMenuBar(workspace: Workspace, openWindow: @escaping () -> Void) {
        guard menuBar == nil else { return }
        menuBar = MenuBarController(workspace: workspace, openWindow: openWindow)
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

    func applicationWillTerminate(_ notification: Notification) { menuBar?.invalidate() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Resolve SwiftUI's window action inside the scene's environment.
private struct FolioWindowLifecycle: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AppDelegate
    let workspace: Workspace
    func body(content: Content) -> some View {
        content
            .background(FolioWindowCapture { appDelegate.mainWindow = $0 })
            .onAppear {
                appDelegate.workspace = workspace
                appDelegate.installMenuBar(workspace: workspace) {
                    if let window = appDelegate.mainWindow, NSApp.windows.contains(window) {
                        window.deminiaturize(nil)
                        window.makeKeyAndOrderFront(nil)
                    } else { openWindow(id: "main") }
                    NSApp.activate(ignoringOtherApps: true)
                }
                QAHarness.startIfRequested(workspace)
            }
    }
}

/// Identify the workspace window without depending on its title or Settings windows.
private struct FolioWindowCapture: NSViewRepresentable {
    let capture: (NSWindow) -> Void
    func makeNSView(context: Context) -> CaptureView { CaptureView(capture: capture) }
    func updateNSView(_ nsView: CaptureView, context: Context) {}
    final class CaptureView: NSView {
        let capture: (NSWindow) -> Void
        init(capture: @escaping (NSWindow) -> Void) { self.capture = capture; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { capture(window) }
        }
    }
}

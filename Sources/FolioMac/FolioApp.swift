import SwiftUI

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = Workspace()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup("Folio", id: "main") {
            WorkspaceView(workspace: workspace)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import PDF…", action: workspace.choosePDF).keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Export PDF Copy…", action: workspace.exportCopy)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(workspace.document == nil)
            }
            CommandMenu("Reader") {
                Button("Library") { workspace.showLibrary() }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Find in PDF…") { workspace.showFind = true }.keyboardShortcut("f")
                    .disabled(workspace.document == nil)
                Button("Add Note…") { workspace.showNoteEditor = true }.keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(workspace.document == nil)
                Button("Star Current Page", action: workspace.toggleStar).keyboardShortcut("d")
                    .disabled(workspace.document == nil)
            }
        }
        Settings { SettingsView().frame(width: 490, height: 360) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

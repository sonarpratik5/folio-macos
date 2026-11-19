import SwiftUI
import FolioCore

struct WorkspaceView: View {
    @ObservedObject var workspace: Workspace
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 290)
        } detail: {
            Group {
                if workspace.reading, workspace.document != nil {
                    ReaderView(workspace: workspace)
                } else if workspace.section == .conversations {
                    ConversationsView(workspace: workspace)
                } else if workspace.section == .insights {
                    InsightsView(workspace: workspace)
                } else {
                    LibraryView(workspace: workspace, onAsk: { workspace.present(.assistant, for: $0) })
                }
            }
            .background(FolioBackdrop())
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !workspace.reading {
                        Menu {
                            Button("Open folder…", action: workspace.chooseFolder)
                            Button("Import PDF…", action: workspace.choosePDF)
                            Button("Import from arXiv…") { workspace.showArxivImport = true }
                        } label: { Label("Import", systemImage: "folder.badge.plus") }
                            .help("Import PDF (⌘O) or from arXiv (⇧⌘I)").disabled(workspace.repository == nil)
                    }
                }
            }
        }
        .onChange(of: workspace.reading, initial: true) { _, reading in
            columnVisibility = reading ? .detailOnly : .all
        }
        // Apply to the whole split view so the traffic-light and title regions share one surface.
        .toolbarBackground(FolioTheme.panelLeft, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .tint(FolioTheme.accent)
        .foregroundStyle(FolioTheme.ink)
        .sheet(isPresented: $workspace.showArxivImport) {
            ArxivImportSheet(workspace: workspace).tint(FolioTheme.accent)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "pdf" }
            guard !pdfs.isEmpty, workspace.repository != nil else { return false }
            workspace.importPDFs(pdfs)
            return true
        }
        .alert("Folio couldn’t complete that action", isPresented: Binding(
            get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } }
        )) { Button("OK") { workspace.errorMessage = nil } } message: { Text(workspace.errorMessage ?? "") }
    }

    private var sidebar: some View { LibrarySidebar(workspace: workspace) }
}

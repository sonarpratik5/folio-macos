import SwiftUI
import FolioCore

struct WorkspaceView: View {
    @ObservedObject var workspace: Workspace
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("design") private var design = "classic"

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 290)
        } detail: {
            Group {
                if workspace.reading, workspace.document != nil {
                    ReaderView(workspace: workspace)
                } else {
                    LibraryView(workspace: workspace)
                }
            }
            .background(FolioTheme.background)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: workspace.choosePDF) { Label("Import PDF", systemImage: "folder.badge.plus") }
                        .help("Import PDF (⌘O)").disabled(workspace.repository == nil)
                    if workspace.reading {
                        Button(action: workspace.exportCopy) { Label("Export PDF Copy", systemImage: "square.and.arrow.up") }
                            .help("Export PDF copy (⇧⌘S)")
                        Button { workspace.inspector.toggle() } label: {
                            Label("Toggle Inspector", systemImage: "sidebar.right")
                        }
                    }
                }
            }
        }
        .tint(design == "studio" ? FolioTheme.studioAccent : FolioTheme.accent)
        .foregroundStyle(FolioTheme.ink)
        .alert("Folio couldn’t complete that action", isPresented: Binding(
            get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } }
        )) { Button("OK") { workspace.errorMessage = nil } } message: { Text(workspace.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "book.closed").font(.title3)
                Text("folio.").font(.system(size: 30, weight: .semibold, design: .serif))
            }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
            Button(action: workspace.choosePDF) { Label("Import PDF", systemImage: "folder")
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5) }
                .buttonStyle(.borderedProminent).padding(.horizontal, 16).disabled(workspace.repository == nil)
            List {
                Section("Library") {
                    ForEach([LibrarySection.all, .opened]) { item in navigation(item) }
                }
                Section("Saved work") {
                    ForEach([LibrarySection.notes, .starred]) { item in navigation(item) }
                }
                if let paper = workspace.activePaper {
                    Section("In your reader") {
                        Button { workspace.reading = true } label: {
                            Label(paper.title, systemImage: "book.pages").lineLimit(2)
                        }.buttonStyle(.plain).padding(.vertical, 5)
                    }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
            Divider().padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 15) {
                Button(action: workspace.sample) { Label("Sample paper", systemImage: "doc.text") }
                    .disabled(workspace.repository == nil)
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                Label("Stored on this Mac", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.plain).padding(20)
        }
        .background(.regularMaterial)
    }

    private func navigation(_ item: LibrarySection) -> some View {
        Button {
            workspace.section = item
            workspace.showLibrary()
        } label: {
            HStack {
                Label(item.rawValue, systemImage: item.symbol)
                Spacer()
                if item == .all { Text("\(workspace.papers.count)").foregroundStyle(.secondary).font(.caption) }
            }.padding(.vertical, 6).padding(.horizontal, 7)
                .background(workspace.section == item && !workspace.reading ? FolioTheme.accent.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
}

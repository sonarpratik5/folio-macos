import SwiftUI
import FolioCore

/// A quiet library destination; inspecting a paper does not replace the open reader document.
struct InsightsView: View {
    @ObservedObject var workspace: Workspace
    private var selected: PaperRecord? {
        workspace.papers.first { $0.id == workspace.insightsPaperID }
            ?? workspace.activePaper ?? workspace.papers.max { $0.lastOpened < $1.lastOpened }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Insights").font(FolioTheme.heading(38)).accessibilityAddTraits(.isHeader)
                    Text("Understand the paper. Follow the sources.").foregroundStyle(.secondary)
                }
                Spacer()
                if let selected {
                    Button { workspace.open(selected) } label: { Label("Read paper", systemImage: "arrow.up.right") }
                        .buttonStyle(FolioPrimaryButtonStyle())
                }
            }
            if let selected {
                Picker("Paper", selection: Binding(get: { selected.id }, set: { workspace.insightsPaperID = $0 })) {
                    ForEach(workspace.papers) { Text($0.title).tag($0.id) }
                }
                .labelsHidden().accessibilityLabel("Paper for insights")
                InsightsPaper(workspace: workspace, paper: selected).id(selected.id)
            } else {
                ContentUnavailableView {
                    Label("Choose a paper to explore", systemImage: "lightbulb")
                } description: {
                    Text("Import a PDF to see its abstract, key sentences and a source-backed overview.")
                } actions: {
                    Button("Import PDF…", action: workspace.choosePDF).disabled(workspace.repository == nil)
                }
            }
        }
        .padding(28).frame(maxWidth: 960).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Insights")
    }
}

private struct InsightsPaper: View {
    @ObservedObject var workspace: Workspace
    let paper: PaperRecord
    @StateObject private var model = PaperAssistantModel()
    var body: some View {
        GlancePanel(workspace: workspace, model: model, paper: paper)
    }
}

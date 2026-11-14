import SwiftUI
import PDFKit
import FolioCore

struct ReaderView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var reader: ReaderState
    @FocusState private var pageFocused: Bool
    init(workspace: Workspace) { self.workspace = workspace; reader = workspace.reader }
    @State private var pageInput = "1"

    var body: some View {
        VStack(spacing: 0) {
            tools.padding(.horizontal, 14).frame(height: 53).background(FolioTheme.strip)
            FolioHairline()
            HStack(spacing: 0) {
            HSplitView {
                if workspace.showDocumentNavigation {
                    DocumentSidebar(workspace: workspace, reader: reader)
                        .overlay(alignment: .trailing) { FolioHairline(vertical: true) }
                        .frame(minWidth: 168, idealWidth: 208, maxWidth: 320)
                }
                PDFCanvas(workspace: workspace).background(FolioTheme.canvas).frame(minWidth: 360)
                if workspace.inspector {
                    inspector
                        .overlay(alignment: .leading) { FolioHairline(vertical: true) }
                        .frame(minWidth: 280, idealWidth: workspace.panel == .notes ? 295 : 340, maxWidth: 460)
                }
            }

                FolioHairline(vertical: true)
                ReaderPanelRail(workspace: workspace)
            }
            FolioHairline()
            HStack {
                Text(workspace.activePaper?.title ?? "").lineLimit(1)
                Spacer()
                icon("Previous page", "chevron.left") { workspace.go(to: workspace.page - 1) }.disabled(workspace.page <= 1)
                TextField("Page", text: $pageInput).focused($pageFocused).frame(width: 35).textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center).onSubmit { workspace.go(to: Int(pageInput) ?? workspace.page); pageInput = String(workspace.page) }
                    .accessibilityLabel("Page number")
                Text("of \(workspace.document?.pageCount ?? 0)")
                icon("Next page", "chevron.right") { workspace.go(to: workspace.page + 1) }
                    .disabled(workspace.page >= (workspace.document?.pageCount ?? 0))
                FolioHairline(vertical: true).frame(height: 12)
                Label(workspace.saveFailed ? "Edit not saved" : "Saved on this Mac", systemImage: workspace.saveFailed ? "exclamationmark.circle" : "checkmark.circle")
            }.font(.system(size: 12)).foregroundStyle(FolioTheme.muted).padding(.horizontal, 16).frame(height: 44)
                .background(FolioTheme.footer)
        }
        .navigationTitle(workspace.activePaper?.title ?? "Reader")

        .onChange(of: workspace.activeID, initial: true) { _, _ in workspace.ensureAIStore() }
        .onChange(of: workspace.page, initial: true) { _, value in pageInput = String(value) }
        .onChange(of: reader.focusPageTick) { _, _ in pageFocused = true }
    }

    private var tools: some View {
        ViewThatFits(in: .horizontal) {
            toolContents
            ScrollView(.horizontal, showsIndicators: false) { toolContents }
        }
    }

    private var toolContents: some View {
        HStack(spacing: 9) {
            icon("Back to library", "chevron.backward") { workspace.showLibrary() }
            Button { workspace.present(.overview) } label: { Label("Insights", systemImage: "lightbulb") }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                .help("Open this paper’s Insights page (⌥⌘G)").accessibilityLabel("Paper insights")
            icon("Show document navigation", "sidebar.left", active: workspace.showDocumentNavigation) { workspace.showDocumentNavigation.toggle() }
            FolioHairline(vertical: true).frame(height: 19)
            ForEach(PDFTool.allCases) { tool in
                Button { workspace.chooseTool(tool) } label: {
                    Image(systemName: tool.symbol)
                }.buttonStyle(ReaderIconStyle(active: workspace.tool == tool))
                    .help("\(tool.label): \(tool.hint)").accessibilityLabel(tool.label)
                    .accessibilityAddTraits(workspace.tool == tool ? .isSelected : [])
            }
            if workspace.tool == .highlight || workspace.tool == .underline || workspace.tool == .note || workspace.tool == .text || (workspace.selectedAnnotation != nil && workspace.selectedAnnotation?.type != "Stamp") {
                colorSwatches
            }
            if let annotation = workspace.selectedAnnotation {
                if annotation.type == "FreeText" {
                    Picker("Text size", selection: Binding(get: { annotation.font?.pointSize ?? workspace.fontSize }, set: workspace.resizeFont)) {
                        ForEach(Array(Set([CGFloat(12), 14, 16, 18, 20, 24, 32, annotation.font?.pointSize ?? 16])).sorted(), id: \.self) { value in
                            Text("\(Int(value)) pt").tag(value)
                        }
                    }.labelsHidden().frame(width: 70).help("Text size")
                }
                if annotation.type == "Text" || annotation.type == "FreeText" {
                    icon("Edit annotation", "square.and.pencil") { workspace.edit(annotation) }
                } else if annotation.type == "Highlight" || annotation.type == "Underline" {
                    icon("Attach a note", "note.text.badge.plus") { workspace.attachNote(to: annotation) }
                }
                icon("Delete annotation", "trash", workspace.deleteSelection)
                icon("Done editing", "checkmark") { workspace.select(nil) }
            }
            FolioHairline(vertical: true).frame(height: 19)
            icon("Undo annotation (⌘Z)", "arrow.uturn.backward", workspace.undoAnnotation).disabled(!workspace.canUndo)
            icon("Redo annotation (⇧⌘Z)", "arrow.uturn.forward", workspace.redoAnnotation).disabled(!workspace.canRedo)
            Spacer(minLength: 4)
            ReaderViewControls(reader: reader)
            FolioHairline(vertical: true).frame(height: 19)
            ReaderSearchField(workspace: workspace, reader: reader)
            Menu {
                Button(workspace.isStarred ? "Unstar this page" : "Star this page", action: workspace.toggleStar)
                Divider()
                Button("Import PDF…", action: workspace.choosePDF)
                    .disabled(workspace.repository == nil)
                Button("Add Writing Page After This Page") { workspace.insertWritingPage(after: workspace.page) }
                Button("Add Writing Page at End") { workspace.insertWritingPage(after: nil) }
                Button("Export PDF Copy…", action: workspace.exportCopy)
                Button("Paste image") { NSApp.sendAction(#selector(ToolPDFView.paste(_:)), to: workspace.pdfView, from: nil) }
                    .disabled(!NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil))
            } label: { Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).foregroundStyle(FolioTheme.iconIdle) }
                .menuStyle(.borderlessButton).fixedSize().help("More page actions")
                .accessibilityLabel("More page actions")
            icon("Show side panel", "sidebar.right", active: workspace.inspector) { workspace.inspector.toggle() }
        }.buttonStyle(ReaderIconStyle()).frame(height: 30)
    }

    @ViewBuilder private var inspector: some View {
        if workspace.panel != .notes, let paper = workspace.activePaper, let store = workspace.activeAIStore {
            switch workspace.panel {
            case .ask: AskPanel(workspace: workspace, model: store.assistant, paper: paper).id(paper.id)
            case .reviews: ReviewsPanel(workspace: workspace, model: store.reviews, paper: paper).id(paper.id)
            case .map: ConceptMapPanel(workspace: workspace, model: store.concepts, paper: paper).id(paper.id)
            case .notes: NotesInspector(workspace: workspace)
            }
        } else { NotesInspector(workspace: workspace) }
    }

    private func icon(_ label: String, _ symbol: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }.buttonStyle(ReaderIconStyle(active: active))
            .help(label).accessibilityLabel(label)
    }

    /// Four inline color swatches: 15px web-fill circles, the chosen one gets a 1px outline offset by 3px.
    private var colorSwatches: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationPalette.names, id: \.self) { color in
                let chosen = workspace.markColor == color
                Button { workspace.recolor(color) } label: {
                    Circle().fill(Color(AnnotationPalette.web(color))).frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(Color(red: 0.545, green: 0.604, blue: 0.498), lineWidth: 1).frame(width: 21, height: 21).opacity(chosen ? 1 : 0))
                        .frame(width: 24, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help("\(color.capitalized) annotation color").accessibilityLabel("\(color.capitalized) annotation color")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

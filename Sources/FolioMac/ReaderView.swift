import SwiftUI
import PDFKit
import FolioCore

struct ReaderView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var reader: ReaderState
    @FocusState private var pageFocused: Bool
    init(workspace: Workspace) { self.workspace = workspace; reader = workspace.reader }
    @State private var pageInput = "1"
    @State private var writingCollapsed = false
    @State private var writingExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            tools.padding(.horizontal, 10).frame(height: 41).folioChrome(cornerRadius: 14)
                .padding(.horizontal, 8).padding(.vertical, 6)
            FolioHairline()
            HStack(spacing: 0) {
            HSplitView {
                if workspace.showDocumentNavigation {
                    DocumentSidebar(workspace: workspace, reader: reader)
                        .overlay(alignment: .trailing) { FolioHairline(vertical: true) }
                        .frame(minWidth: 168, idealWidth: 208, maxWidth: 320)
                }
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        PDFCanvas(workspace: workspace).background(FolioTheme.canvas).frame(minWidth: 360)
                        if workspace.showWriting {
                            WritingBelowView(workspace: workspace, collapsed: $writingCollapsed,
                                             expanded: $writingExpanded, availableHeight: geometry.size.height)
                                .id("\(workspace.activeID?.uuidString ?? "")-\(workspace.page)")
                        }
                    }
                }.frame(minWidth: 360)
                if workspace.inspector {
                    inspector
                        .overlay(alignment: .leading) { FolioHairline(vertical: true) }
                        .frame(minWidth: workspace.panel == .ask ? 320 : 280,
                               idealWidth: workspace.panel == .notes ? 295 : workspace.panel == .ask ? 380 : 340,
                               maxWidth: 460)
                }
            }

                FolioHairline(vertical: true)
                ReaderPanelRail(workspace: workspace)
            }
        }
        .navigationTitle(workspace.activePaper?.title ?? "Reader")

        .onChange(of: workspace.documentSessionID, initial: true) { _, _ in workspace.ensureAIStore() }
        .onChange(of: workspace.page, initial: true) { _, value in pageInput = String(value) }
        .onChange(of: reader.focusPageTick) { _, _ in pageFocused = true }
    }

    private var tools: some View {
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                toolContents
                ScrollView(.horizontal, showsIndicators: false) { toolContents }
            }
            FolioHairline(vertical: true).frame(height: 19)
            pageNavigation
            if workspace.saveFailed {
                Label("Edit not saved", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(FolioTheme.warning).fixedSize()
            }
        }
    }

    private var pageNavigation: some View {
        HStack(spacing: 3) {
            icon("Return to previous passage", "arrow.uturn.backward") { workspace.returnToPassage() }.disabled(workspace.passageHistory.isEmpty)
            icon("Previous page", "chevron.left") { workspace.go(to: workspace.page - 1) }
                .disabled(workspace.page <= 1)
            TextField("Page", text: $pageInput).focused($pageFocused)
                .frame(width: 35).textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onSubmit {
                    workspace.go(to: Int(pageInput) ?? workspace.page)
                    pageInput = String(workspace.page)
                }
                .accessibilityLabel("Page number")
                .help("Go to page (G)")
            Text("of \(workspace.document?.pageCount ?? 0)")
                .foregroundStyle(FolioTheme.muted)
            icon("Next page", "chevron.right") { workspace.go(to: workspace.page + 1) }
                .disabled(workspace.page >= (workspace.document?.pageCount ?? 0))
        }
        .font(.system(size: 12).monospacedDigit()).fixedSize()
    }

    private var toolContents: some View {
        HStack(spacing: 9) {
            icon("Back to library", "chevron.backward") { workspace.showLibrary() }
            Button { workspace.present(.overview) } label: { Image(systemName: "rectangle.3.group") }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                .help("Open this paper’s Insights page (⌥⌘G)").accessibilityLabel("Paper overview")
            icon("Show document navigation", "sidebar.left", active: workspace.showDocumentNavigation) { workspace.showDocumentNavigation.toggle() }
            FolioHairline(vertical: true).frame(height: 19)
            ForEach(PDFTool.allCases) { tool in
                Button { workspace.chooseTool(tool) } label: {
                    Image(systemName: tool.symbol)
                }.buttonStyle(ReaderIconStyle(active: workspace.tool == tool))
                    .help("\(tool.label): \(tool.hint)").accessibilityLabel(tool.label)
                    .accessibilityAddTraits(workspace.tool == tool ? .isSelected : [])
            }
            Button { workspace.chooseInsightsMode() } label: { Label("Insights", systemImage: "lightbulb") }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8).frame(height: 30)
                .background(workspace.insightsMode ? FolioTheme.iconActiveBg : .clear, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(workspace.insightsMode ? FolioTheme.iconActiveInk : FolioTheme.iconIdle)
                .help("Insights on selection (I). Select text to explain it; V returns to plain selection.")
                .accessibilityLabel("Insights on selection").accessibilityAddTraits(workspace.insightsMode ? .isSelected : [])
            Menu {
                Button(workspace.skimEnabled ? "Turn Skim off" : "Turn Skim on", action: workspace.toggleSkim)
                if workspace.skimEnabled {
                    Divider()
                    ForEach(SkimFacet.allCases) { facet in
                        Toggle(facet.label, isOn: Binding(get: { workspace.skimFacets.contains(facet) }, set: { _ in workspace.toggleSkimFacet(facet) }))
                    }
                    if workspace.skimLoading { Text("Classifying on this Mac…") }
                    else if let error = workspace.skimError {
                        Text(error)
                        Button("Retry") { workspace.clearSkim(); workspace.toggleSkim() }
                    } else {
                        ForEach(SkimFacet.allCases) { facet in
                            Text("\(facet.label): \(workspace.skimMarks.filter { $0.facet == facet }.count)")
                        }
                        if workspace.skimMarks.isEmpty { Text("No confident passages found. Scanned PDFs need a text layer.") }
                    }
                }
            } label: {
                Label(workspace.skimLoading ? "Skimming…" : workspace.skimError != nil ? "Skim failed" : "Skim", systemImage: "highlighter")
                    .foregroundStyle(workspace.skimEnabled ? FolioTheme.iconActiveInk : FolioTheme.iconIdle)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Local Skim highlights: Goal (orange), Method (blue), Result (green). Click to enable, filter or turn off.")
            .accessibilityLabel("Skim highlights")
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
                Button(workspace.showWriting ? "Close Page Notes" : "Write Below This Page", action: workspace.toggleWriting)
                Button("Export Study Copy…") { workspace.exportCopy(study: true) }
                Button("Add Writing Page After This Page") { workspace.insertWritingPage(after: workspace.page) }
                Button("Add Writing Page at End") { workspace.insertWritingPage(after: nil) }
                Button("Export PDF Copy…", action: { workspace.exportCopy() })
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
            case .insight: NotesInspector(workspace: workspace)
            case .ask: AskPanel(workspace: workspace, model: store.assistant, paper: paper).id(ObjectIdentifier(store))
            case .reviews: ReviewsPanel(workspace: workspace, model: store.reviews, paper: paper).id(ObjectIdentifier(store))
            case .map: ConceptMapPanel(workspace: workspace, model: store.concepts, paper: paper).id(ObjectIdentifier(store))
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
                    Circle().fill(Color(AnnotationPalette.swatch(color))).frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(Color(red: 0.545, green: 0.604, blue: 0.498), lineWidth: 1).frame(width: 21, height: 21).opacity(chosen ? 1 : 0))
                        .frame(width: 24, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help("\(color.capitalized) annotation color").accessibilityLabel("\(color.capitalized) annotation color")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

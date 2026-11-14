import SwiftUI
import PDFKit
import FolioCore

struct ReaderView: View {
    @ObservedObject var workspace: Workspace
    @State private var navigationTab = "pages"
    @State private var pageInput = "1"
    @State private var noteDraft = ""
    @State private var findQuery = ""
    @State private var findResults: [PDFSelection] = []
    @State private var match = 0
    @State private var inspectorTab = "notes"
    @State private var markColor = "yellow"
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tools.padding(.horizontal, 14).padding(.vertical, 9).background(FolioTheme.card)
            Divider()
            if workspace.showFind { findBar }
            HSplitView {
                documentNavigation.frame(minWidth: 145, idealWidth: 170, maxWidth: 235)
                PDFCanvas(workspace: workspace).frame(minWidth: 360)
                if workspace.inspector { inspector.frame(minWidth: 245, idealWidth: 280, maxWidth: 390) }
            }
            HStack {
                Text(workspace.activePaper?.title ?? "").lineLimit(1)
                Spacer()
                Text("Page \(workspace.page) of \(workspace.document?.pageCount ?? 0)")
                Divider().frame(height: 12)
                Label("Saved on this Mac", systemImage: "checkmark.circle")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
                .background(FolioTheme.card)
        }
        .navigationTitle(workspace.activePaper?.title ?? "Reader")
        .sheet(isPresented: $workspace.showNoteEditor) { noteEditor }
        .onChange(of: workspace.page, initial: true) { _, value in pageInput = String(value) }
        .onChange(of: workspace.activeID) { _, _ in findResults = []; findQuery = ""; noteDraft = "" }
        .onChange(of: workspace.showFind) { _, shown in findFocused = shown }
    }

    private var tools: some View {
        ViewThatFits(in: .horizontal) {
            toolContents
            ScrollView(.horizontal, showsIndicators: false) { toolContents }
        }
    }

    private var toolContents: some View {
        HStack(spacing: 13) {
            Menu {
                Picker("Highlight color", selection: $markColor) {
                    Text("Yellow").tag("yellow"); Text("Green").tag("green")
                    Text("Blue").tag("blue"); Text("Pink").tag("pink")
                }
            } label: { Image(systemName: "circle.fill").foregroundStyle(Color(selectedColor)) }
                .help("Annotation color").menuStyle(.borderlessButton).fixedSize()
            Button { workspace.markSelection(.highlight, color: selectedColor) } label: {
                Label("Highlight", systemImage: "highlighter")
            }.help("Select text, then highlight")
            Button { workspace.markSelection(.underline, color: selectedColor) } label: {
                Label("Underline", systemImage: "underline")
            }.help("Select text, then underline")
            Button { workspace.showNoteEditor = true } label: { Label("Note", systemImage: "note.text.badge.plus") }
            Divider().frame(height: 18)
            icon("Undo annotation", "arrow.uturn.backward") { workspace.annotationUndo.undo() }
                .disabled(!workspace.annotationUndo.canUndo)
            icon("Redo annotation", "arrow.uturn.forward") { workspace.annotationUndo.redo() }
                .disabled(!workspace.annotationUndo.canRedo)
            Divider().frame(height: 18)
            icon("Zoom out", "minus.magnifyingglass") { workspace.pdfView?.autoScales = false; workspace.pdfView?.zoomOut(nil) }
            icon("Fit page", "arrow.up.left.and.arrow.down.right") { workspace.pdfView?.autoScales = true }
            icon("Zoom in", "plus.magnifyingglass") { workspace.pdfView?.autoScales = false; workspace.pdfView?.zoomIn(nil) }
            Spacer(minLength: 8)
            icon("Previous page", "chevron.left") { workspace.go(to: workspace.page - 1) }.disabled(workspace.page <= 1)
            TextField("Page", text: $pageInput).frame(width: 35).textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center).onSubmit { workspace.go(to: Int(pageInput) ?? workspace.page) }
                .accessibilityLabel("Page number")
            icon("Next page", "chevron.right") { workspace.go(to: workspace.page + 1) }
                .disabled(workspace.page >= (workspace.document?.pageCount ?? 0))
            icon("Star current page", workspace.isStarred ? "star.fill" : "star", workspace.toggleStar)
        }.buttonStyle(.borderless).font(.system(size: 12))
    }

    private var selectedColor: NSColor {
        switch markColor {
        case "green": NSColor(srgbRed: 0.66, green: 0.84, blue: 0.69, alpha: 1)
        case "blue": NSColor(srgbRed: 0.61, green: 0.77, blue: 0.96, alpha: 1)
        case "pink": NSColor(srgbRed: 0.95, green: 0.69, blue: 0.76, alpha: 1)
        default: NSColor(srgbRed: 0.96, green: 0.85, blue: 0.42, alpha: 1)
        }
    }

    private var documentNavigation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Document navigation", selection: $navigationTab) {
                Text("Pages").tag("pages"); Text("Outline").tag("outline")
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                if navigationTab == "pages" {
                    LazyVStack(spacing: 5) {
                        ForEach(1..<(max(workspace.document?.pageCount ?? 0, 1) + 1), id: \.self) { page in
                            Button { workspace.go(to: page) } label: {
                                HStack {
                                    Image(systemName: "doc.text")
                                    Text("Page \(page)"); Spacer()
                                    if workspace.activePaper?.starredPages.contains(page) == true {
                                        Image(systemName: "star.fill").font(.caption2)
                                    }
                                }.padding(9).contentShape(Rectangle())
                                    .background(page == workspace.page ? FolioTheme.accent.opacity(0.12) : .clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                    }
                } else if let root = workspace.document?.outlineRoot, root.numberOfChildren > 0 {
                    OutlineEntries(root: root) { destination in workspace.pdfView?.go(to: destination) }
                } else {
                    Text("This PDF has no embedded outline. Use Pages to navigate.")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 16)
                }
            }
        }.padding(12).background(FolioTheme.card)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Inspector", selection: $inspectorTab) {
                Text("Notes").tag("notes"); Text("Overview").tag("overview"); Text("Ask").tag("ask")
            }.pickerStyle(.segmented).labelsHidden()
            if inspectorTab == "notes" {
                HStack {
                    Text("Notes").font(FolioTheme.heading(24)); Spacer()
                    Text("\(workspace.notes.count)").foregroundStyle(.secondary)
                    Button { workspace.showNoteEditor = true } label: { Image(systemName: "plus") }.help("Add note")
                }
                if workspace.notes.isEmpty {
                    EmptyState(symbol: "note.text", title: "Room for your ideas", detail: "Add a note about the current page or a selected passage.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(workspace.notes) { note in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(note.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    HStack {
                                        Button("Page \(note.page)") { workspace.go(to: note.page) }
                                        Spacer()
                                        Button { workspace.deleteNote(note) } label: { Image(systemName: "trash") }
                                            .help("Delete note (available in annotation Undo)")
                                    }.font(.caption).buttonStyle(.borderless)
                                }.padding(14).background(FolioTheme.background, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            } else if inspectorTab == "overview" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        Text("Paper at a glance").font(FolioTheme.heading(25))
                        Text(workspace.activePaper?.title ?? "").fontWeight(.medium)
                        Label("\(workspace.document?.pageCount ?? 0) pages", systemImage: "doc.text")
                        Text("Opening excerpt").font(.headline)
                        Text(String((workspace.document?.page(at: 0)?.string ?? "No selectable text on the first page.").prefix(2600)))
                            .font(.callout).textSelection(.enabled)
                        Divider()
                        Text("This is an on-device excerpt. AI summaries and reviews are planned; see the porting map in the repository.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                EmptyState(symbol: "sparkles", title: "Ask your paper",
                           detail: "AI isn’t connected in this starter. The porting map describes how to add a native provider service. No paper content is sent anywhere.")
            }
            Spacer(minLength: 0)
        }.padding(16).background(FolioTheme.card)
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Note · page \(workspace.page)").font(FolioTheme.heading(25))
            TextEditor(text: $noteDraft).font(.body).frame(height: 180)
                .border(.quaternary).accessibilityLabel("Note text")
            Text("Saved as a PDF comment in your local Folio copy.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { workspace.showNoteEditor = false; noteDraft = "" }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save note") {
                    workspace.addNote(noteDraft)
                    if workspace.errorMessage == nil { workspace.showNoteEditor = false; noteDraft = "" }
                }.keyboardShortcut(.defaultAction).disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 450)
    }

    private var findBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Find in this PDF", text: $findQuery).textFieldStyle(.roundedBorder).focused($findFocused)
                .onSubmit { find() }
            Text(findResults.isEmpty ? "No results" : "\(match + 1) of \(findResults.count)").font(.caption).foregroundStyle(.secondary)
            Button("Find", action: find)
            icon("Previous match", "chevron.up") { revealMatch(match - 1) }.disabled(findResults.isEmpty)
            icon("Next match", "chevron.down") { revealMatch(match + 1) }.disabled(findResults.isEmpty)
            icon("Close Find", "xmark") { workspace.showFind = false; workspace.pdfView?.highlightedSelections = nil }
        }.padding(10).background(FolioTheme.card)
        .onChange(of: findQuery) { _, _ in findResults = []; workspace.pdfView?.highlightedSelections = nil }
    }

    private func find() {
        guard !findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        findResults = workspace.document?.findString(findQuery, withOptions: [.caseInsensitive]) ?? []
        workspace.pdfView?.highlightedSelections = findResults
        revealMatch(0)
    }

    private func revealMatch(_ index: Int) {
        guard !findResults.isEmpty else { return }
        match = (index + findResults.count) % findResults.count
        let selection = findResults[match]
        workspace.pdfView?.setCurrentSelection(selection, animate: true)
        workspace.pdfView?.go(to: selection)
    }

    private func icon(_ label: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }.help(label).accessibilityLabel(label)
    }
}

private struct OutlineEntries: View {
    let root: PDFOutline
    let go: (PDFDestination) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<root.numberOfChildren, id: \.self) { index in
                if let child = root.child(at: index) {
                    Button(child.label ?? "Untitled section") {
                        if let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination { go(destination) }
                    }.buttonStyle(.plain).multilineTextAlignment(.leading)
                    if child.numberOfChildren > 0 {
                        // Type erasure gives recursive native outline rendering a finite SwiftUI type.
                        AnyView(OutlineEntries(root: child, go: go)).padding(.leading, 12)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

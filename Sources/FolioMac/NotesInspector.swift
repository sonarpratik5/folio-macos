import SwiftUI
import FolioCore
import PDFKit
import UniformTypeIdentifiers

/// Thumbnails for images attached to a note; removable when `editable`. Accepts paste and drops.
struct NoteImageStrip: View {
    @ObservedObject var workspace: Workspace
    @Binding var names: [String]
    let editable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !names.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(names, id: \.self) { name in
                            ZStack(alignment: .topTrailing) {
                                if let image = workspace.noteImage(name) {
                                    Image(nsImage: image).resizable().scaledToFill().frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel("Attached image")
                                } else {
                                    RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 64, height: 64)
                                }
                                if editable {
                                    Button { names.removeAll { $0 == name } } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }.buttonStyle(.plain).padding(2).help("Remove image").accessibilityLabel("Remove image")
                                }
                            }
                        }
                    }
                }
            }
            if editable {
                HStack(spacing: 10) {
                    Button { chooseFile() } label: { Label("Attach image", systemImage: "photo.badge.plus") }
                    Button { pasteImage() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                        .disabled(!NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil))
                }.font(.caption).buttonStyle(.borderless)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard editable else { return false }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let image = NSImage(contentsOf: url) else { return }
                    Task { @MainActor in add(image) }
                }
            }
            return true
        }
    }

    private func add(_ image: NSImage) { if let name = workspace.addNoteImage(image) { names.append(name) } }
    private func pasteImage() {
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage { add(image) }
    }
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.message = "Folio keeps a private copy beside your library."
        if panel.runModal() == .OK { panel.urls.compactMap { NSImage(contentsOf: $0) }.forEach(add) }
    }
}

struct NotesInspector: View {
    @ObservedObject var workspace: Workspace
    @State private var query = ""
    @State private var colorFilter: String?
    @State private var editingID: String?
    @State private var draftText = ""
    @State private var draftImages: [String] = []
    @State private var deletedAt: Date?
    @State private var selectionText = ""

    private static let colors: [(String, NSColor)] = AnnotationPalette.names.map { ($0, AnnotationPalette.swatch($0)) }

    private var all: [PaperNote] { _ = workspace.revision; return workspace.notes }
    private var shown: [PaperNote] {
        PDFNotes.filter(all, query: query, color: colorFilter.map { AnnotationPalette.fill($0) }).filter(matchesFilter)
    }
    private func matchesFilter(_ note: PaperNote) -> Bool {
        colorFilter == nil || AnnotationPalette.name(for: note.color) == colorFilter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("PDF NOTES").font(.system(size: 12)).tracking(1.7).foregroundStyle(FolioTheme.eyebrow)
                    Spacer()
                    Button { workspace.beginNote(selection: workspace.pdfView?.currentSelection) } label: { Image(systemName: "plus") }
                        .help("Add note").accessibilityLabel("Add note")
                    Button { workspace.inspector = false } label: { Image(systemName: "xmark") }
                        .help("Close notes").accessibilityLabel("Close notes")
                }.buttonStyle(ReaderIconStyle(size: 26))
                Text("Notes").font(FolioTheme.heading(22)).foregroundStyle(FolioTheme.panelTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            if workspace.pdfView != nil { selectionCard }
            if !all.isEmpty { filterBar }
            content
            if deletedAt != nil {
                HStack {
                    Text("Note deleted").font(.callout)
                    Spacer()
                    Button("Undo") { workspace.undoAnnotation(); deletedAt = nil }.keyboardShortcut("z", modifiers: .command)
                }.folioCard(radius: FolioRadius.control, padding: 10)
            }
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FolioTheme.panelRight)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(FolioTheme.muted).font(.system(size: 11))
            TextField("Search notes", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            ForEach(Self.colors, id: \.0) { name, color in
                Button { colorFilter = colorFilter == name ? nil : name } label: {
                    Circle().fill(Color(color)).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color(red: 0.545, green: 0.604, blue: 0.498), lineWidth: 1).frame(width: 19, height: 19).opacity(colorFilter == name ? 1 : 0))
                        .frame(width: 20, height: 20)
                }.buttonStyle(.plain).help("Show \(name) only").accessibilityLabel("Filter \(name)")
            }
        }.padding(.horizontal, 9).padding(.vertical, 6)
            .background(FolioTheme.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(FolioTheme.fieldLine))
    }

    @ViewBuilder private var selectionCard: some View {
        let text = workspace.pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? selectionText
        if let pdf = workspace.pdfView {
            Color.clear.frame(height: 0)
                .onReceive(NotificationCenter.default.publisher(for: .PDFViewSelectionChanged, object: pdf)) { _ in
                    selectionText = pdf.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
        }
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(text).lineLimit(3).font(.system(size: 14, design: .serif)).foregroundStyle(FolioTheme.quoteInk)
                    .padding(.leading, 9).overlay(alignment: .leading) { Rectangle().fill(FolioTheme.tabActiveLine.opacity(0.6)).frame(width: 2) }
                Button("Add note to selection") { workspace.beginNote(selection: workspace.pdfView?.currentSelection) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(FolioTheme.selectionCard, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(FolioTheme.selectionCardLine))
        }
    }

    @ViewBuilder private var content: some View {
        if all.isEmpty {
            emptyState(heading: "No notes yet", body: "Keep your written notes and attachments for this PDF here.",
                       tip: "Tip: select text, then use Add note.")
        } else if shown.isEmpty {
            Text("No notes match.").font(.callout).foregroundStyle(FolioTheme.muted)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(PDFNotes.grouped(shown), id: \.page) { group in
                        Text("Page \(group.page)".uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2)
                            .foregroundStyle(FolioTheme.sectionTitle).padding(.top, 4).accessibilityAddTraits(.isHeader)
                        ForEach(group.notes) { note in card(note) }
                    }
                }
            }
        }
        Spacer(minLength: 0)
    }

    private func emptyState(heading: String, body: String, tip: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(FolioTheme.heading(19)).foregroundStyle(FolioTheme.emptyHeading)
            Text(body).font(.system(size: 13)).foregroundStyle(FolioTheme.noteInk).fixedSize(horizontal: false, vertical: true)
            Text(tip).font(.system(size: 12)).foregroundStyle(FolioTheme.noteInk).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(FolioTheme.tipBox, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(FolioTheme.tipLine))
        }.padding(.top, 8)
    }

    private func markColor(_ color: NSColor) -> Color {
        Color(AnnotationPalette.name(for: color).map(AnnotationPalette.swatch) ?? color.withAlphaComponent(1))
    }

    private func cardShell<Content: View>(color: Color, selected: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) { content() }
            .padding(.vertical, 10).padding(.horizontal, 12).padding(.leading, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FolioTheme.card, in: shape)
            .overlay(shape.strokeBorder(FolioTheme.cardLine))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5).fill(color).frame(width: 3)
            }
            .overlay(shape.strokeBorder(selected ? FolioTheme.rowActiveLine : .clear, lineWidth: 2))
    }

    private func meta(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12)).foregroundStyle(FolioTheme.noteInk)
        }
    }

    @ViewBuilder private func card(_ note: PaperNote) -> some View {
        let editing = editingID == note.id
        let color = markColor(note.color)
        cardShell(color: color, selected: workspace.selectedAnnotation === note.annotation) {
            if !note.quote.isEmpty {
                Text(note.quote).lineLimit(3).font(.system(size: 15, design: .serif)).foregroundStyle(FolioTheme.quoteInk).lineSpacing(4)
            }
            if editing {
                TextEditor(text: $draftText).font(.system(size: 13)).frame(minHeight: 70, maxHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(FolioTheme.line)).accessibilityLabel("Note text")
                NoteImageStrip(workspace: workspace, names: $draftImages, editable: true)
            } else {
                Button { workspace.go(to: note.page); workspace.select(note.annotation) } label: {
                    Text(note.body.isEmpty ? "Image attachment" : note.body).font(.system(size: 13)).foregroundStyle(FolioTheme.ink.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Go to this note on page \(note.page)")
                if !note.images.isEmpty { NoteImageStrip(workspace: workspace, names: .constant(note.images), editable: false) }
            }
            FolioHairline().opacity(0.5)
            HStack(spacing: 12) {
                meta(color, "Note · Page \(note.page)")
                Spacer()
                if editing {
                    Button("Save") {
                        if workspace.updateNote(note, body: draftText, images: draftImages) { editingID = nil }
                    }
                        .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draftImages.isEmpty)
                    Button("Cancel") { editingID = nil }
                } else {
                    Button { editingID = note.id; draftText = note.body; draftImages = note.images } label: { Image(systemName: "pencil") }
                        .help("Edit note").accessibilityLabel("Edit note")
                    Button { workspace.go(to: note.page); workspace.select(note.annotation) } label: { Image(systemName: "location") }
                        .help("Show on page").accessibilityLabel("Show on page")
                }
                Button { workspace.deleteNote(note); deletedAt = Date(); expireUndo() } label: { Image(systemName: "trash") }
                    .help("Delete note (undo available)").accessibilityLabel("Delete note")
            }.font(.caption).buttonStyle(.borderless)
        }
    }

    private func expireUndo() {
        let stamp = deletedAt
        Task { try? await Task.sleep(for: .seconds(8)); if deletedAt == stamp { deletedAt = nil } }
    }
}

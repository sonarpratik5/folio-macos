import SwiftUI
import PDFKit
import FolioCore

struct AnnotationDraft: Identifiable {
    let id = UUID()
    let page: PDFPage
    var bounds: CGRect
    let kind: PDFAnnotationSubtype
    let text: String
    let quote: String
    let selection: PDFSelection?
    var attachedGroup: String? = nil
    var images: [String] = []
    var original: PDFAnnotation? = nil
    /// Inline text formatting chosen while editing (nil ink = keep the existing/toolbar color).
    var ink: NSColor? = nil
    var bold = false
}

struct AnnotationEditor: View {
    @ObservedObject var workspace: Workspace
    let draft: AnnotationDraft
    @State private var text: String
    @State private var size: CGFloat
    @State private var images: [String]
    @FocusState private var focused: Bool

    init(workspace: Workspace, draft: AnnotationDraft) {
        self.workspace = workspace; self.draft = draft
        _text = State(initialValue: draft.text)
        _images = State(initialValue: draft.original.map(PDFNotes.images) ?? draft.images)
        _size = State(initialValue: draft.original?.font?.pointSize ?? workspace.fontSize)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Note").font(.headline)
                Spacer()
            }
            if !draft.quote.isEmpty {
                Text(draft.quote).lineLimit(3).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextEditor(text: $text).font(.system(size: 14))
                .frame(height: 130).focused($focused).accessibilityLabel("Note text")
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            if draft.kind == .text {
                NoteImageStrip(workspace: workspace, names: $images, editable: true)
            }
            HStack {
                Button("Cancel") { workspace.editor = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") { workspace.saveEditor(draft, text: text, size: size) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(16).frame(width: 320).onAppear { focused = true }
            .onChange(of: text) { _, value in workspace.pendingEditorText = value; workspace.persistNoteDraft(draft, text: value) }
            .onChange(of: size) { _, value in workspace.pendingEditorSize = value }
            .onChange(of: images) { _, value in workspace.pendingEditorImages = value }
    }
}

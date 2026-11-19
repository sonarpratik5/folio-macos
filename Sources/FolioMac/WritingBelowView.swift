import SwiftUI
import FolioCore
import PDFKit

/// Page-local writing stays small; longer notes scroll until explicitly expanded.
struct WritingBelowView: View {
    @ObservedObject var workspace: Workspace
    @Binding var collapsed: Bool
    @Binding var expanded: Bool
    let availableHeight: CGFloat
    @State private var text = ""
    @State private var target: PDFPage?
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var pending: Bool { workspace.pendingWriting != nil }
    private var editorHeight: CGFloat {
        // Even expanded, leave at least two thirds of the reader for the paper.
        max(0, min(expanded ? 220 : 64, availableHeight / 3 - 40))
    }

    var body: some View {
        VStack(spacing: 0) {
            FolioHairline()
            HStack(spacing: 8) {
                Button {
                    collapsed.toggle()
                    focused = !collapsed
                } label: {
                    Label("Page \(workspace.page) notes", systemImage: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .help(collapsed ? "Show page notes" : "Collapse page notes")
                .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
                Spacer(minLength: 0)
                if pending {
                    Button(workspace.saveFailed ? "Retry save" : "Save") { save() }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(workspace.saveFailed ? FolioTheme.warning : FolioTheme.accent)
                        .help("Save page notes to your managed PDF (⌘Return)")
                } else if !text.isEmpty {
                    Image(systemName: "checkmark").font(.system(size: 10))
                        .foregroundStyle(.secondary).accessibilityLabel("Page notes saved")
                        .help("Saved in your managed PDF. Export Study Copy includes continuation sheets.")
                }
                if !collapsed {
                    control(expanded ? "Use compact notes" : "Expand notes", expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                        expanded.toggle()
                    }
                }
                control("Close page notes", "xmark", workspace.toggleWriting)
            }
            .buttonStyle(.plain).foregroundStyle(FolioTheme.muted)
            .padding(.horizontal, 12).frame(height: 32)

            if !collapsed {
                TextEditor(text: Binding(get: { text }, set: stage))
                    .font(.system(size: 13)).scrollContentBackground(.hidden)
                    .focused($focused)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Add notes for this page…").font(.system(size: 13)).foregroundStyle(.tertiary)
                                .padding(.leading, 5).padding(.top, 1).allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(height: editorHeight)
                    .padding(.horizontal, 8).padding(.bottom, 8)
                    .accessibilityLabel("Notes below PDF page \(workspace.page)")
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        save(); return .handled
                    }
            }
        }
        .background(FolioTheme.card)
        .onAppear {
            target = workspace.document?.page(at: workspace.page - 1)
            reload()
            focused = !collapsed
        }
        .onChange(of: workspace.revision) { _, _ in
            if !pending { reload() }
        }
        .onChange(of: workspace.pendingWriting == nil) { _, cleared in
            if cleared { reload() }
        }
        .onDisappear { saveTask?.cancel(); workspace.flushWriting() }
    }

    private func control(_ label: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .help(label).accessibilityLabel(label)
    }

    private func reload() {
        if let pending = workspace.pendingWriting, pending.page === target { text = pending.text }
        else { text = target.flatMap { StudyCopy.writing(on: $0)?.contents } ?? "" }
    }

    private func stage(_ value: String) {
        guard let target, let document = workspace.document, document.index(for: target) != NSNotFound else { return }
        text = value
        // Stage synchronously so close/navigation cannot race SwiftUI's onChange delivery.
        saveTask?.cancel()
        guard value != (StudyCopy.writing(on: target)?.contents ?? "") else {
            workspace.pendingWriting = nil
            return
        }
        workspace.pendingWriting = (target, value)
        saveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            workspace.flushWriting()
        }
    }

    private func save() {
        saveTask?.cancel()
        workspace.flushWriting()
    }
}

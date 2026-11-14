import SwiftUI
import FolioCore

/// Accepts an arXiv id or link, downloads only after the explicit Download click, then imports a managed copy.
struct ArxivImportSheet: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var task: Task<Void, Never>?
    @State private var progress: Double?
    @State private var failure: String?

    private var parsed: String? { ArxivID.parse(input) }
    private var working: Bool { task != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FolioHeader("Import from arXiv", subtitle: "Paste an arXiv ID or link. Folio downloads the PDF only when you press Download, then keeps a private copy.")
            TextField("2401.12345 or https://arxiv.org/abs/…", text: $input)
                .textFieldStyle(.roundedBorder).disabled(working)
                .onSubmit(start).onChange(of: input) { _, _ in failure = nil }
                .accessibilityLabel("arXiv ID or link")
            Group {
                if let failure {
                    FolioNotice(text: failure, tone: .error)
                } else if working {
                    HStack(spacing: 10) {
                        if let progress { FolioProgressBar(value: progress).frame(maxWidth: 220) } else { ProgressView().controlSize(.small) }
                        Text("Downloading \(parsed ?? "")…").foregroundStyle(.secondary)
                    }
                } else if let parsed {
                    Label("Paper \(parsed)", systemImage: "checkmark.circle").foregroundStyle(FolioTheme.accent)
                } else if !input.trimmingCharacters(in: .whitespaces).isEmpty {
                    Label("That doesn’t look like an arXiv ID or link.", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                } else { Text(" ") }
            }.font(.callout)
            HStack {
                Spacer()
                Button(working ? "Cancel Download" : "Cancel") {
                    if working { task?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction)
                Button("Download", action: start).keyboardShortcut(.defaultAction)
                    .buttonStyle(FolioPrimaryButtonStyle()).disabled(parsed == nil || working)
            }
        }
        .padding(26).frame(width: 480).folioSheetBackground()
        .onDisappear { task?.cancel() }
    }

    private func start() {
        guard let id = parsed, !working else { return }
        failure = nil; progress = nil
        task = Task {
            defer { task = nil }
            do {
                let result = try await ArxivDownloader().download(id: id) { value in
                    Task { @MainActor in progress = value }
                }
                defer { try? FileManager.default.removeItem(at: result.file.deletingLastPathComponent()) }
                try Task.checkCancellation()
                workspace.importPDFs([result.file], title: result.title)
                if workspace.errorMessage == nil { dismiss() }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch { failure = error.localizedDescription }
        }
    }
}

/// Shared delete confirmation wording: the managed copy goes, the imported original stays.
extension View {
    func confirmRemoval(of paper: Binding<PaperRecord?>, perform: @escaping (PaperRecord) -> Void) -> some View {
        confirmationDialog("Remove “\(paper.wrappedValue?.title ?? "")” from your library?",
                           isPresented: Binding(get: { paper.wrappedValue != nil }, set: { if !$0 { paper.wrappedValue = nil } }),
                           titleVisibility: .visible, presenting: paper.wrappedValue) { item in
            Button("Remove from Library", role: .destructive) { perform(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Folio’s private copy, its notes and highlights are deleted. The original file you imported is not touched. This can’t be undone.")
        }
    }
}

struct RenamePaperSheet: View {
    let paper: PaperRecord
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(paper: PaperRecord, onSave: @escaping (String) -> Void) {
        self.paper = paper; self.onSave = onSave
        _title = State(initialValue: paper.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FolioHeader("Rename Paper", size: 24)
            TextField("Title", text: $title).textFieldStyle(.roundedBorder).onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: save).keyboardShortcut(.defaultAction).buttonStyle(FolioPrimaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 420).folioSheetBackground()
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSave(title); dismiss()
    }
}

import SwiftUI
import PDFKit

struct PDFCanvas: NSViewRepresentable {
    @ObservedObject var workspace: Workspace

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = true
        view.backgroundColor = NSColor(FolioTheme.canvas)
        workspace.pdfView = view
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard view.document !== workspace.document else { return }
        // Setting the document can synchronously emit page 1. Restore the intended position.
        let target = workspace.page
        context.coordinator.restoring = true
        view.document = workspace.document
        if let page = workspace.document?.page(at: target - 1) { view.go(to: page) }
        context.coordinator.restoring = false
        workspace.pdfView = view
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) { coordinator.detach() }
    func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }

    @MainActor
    final class Coordinator: NSObject {
        let workspace: Workspace
        var restoring = false
        init(workspace: Workspace) { self.workspace = workspace }
        func attach(_ view: PDFView) {
            NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)
        }
        func detach() { NotificationCenter.default.removeObserver(self) }
        @objc private func pageChanged(_ notification: Notification) {
            guard !restoring, let view = notification.object as? PDFView,
                  let document = view.document, let page = view.currentPage else { return }
            let number = document.index(for: page) + 1
            // Leave the representable update before publishing state.
            Task { @MainActor [weak self, weak document] in
                guard let self, self.workspace.document === document else { return }
                self.workspace.changedPage(number)
            }
        }
    }
}

import XCTest
import PDFKit
import SwiftUI
import AppKit
import FolioCore
@testable import FolioMac

final class WebStyleRenderTests: XCTestCase {
    func testHighlightFillMatchesWebAtMultiply() {
        // Web: fill at .43 multiply on white. Stored color is that composite.
        let web = AnnotationPalette.web("yellow").usingColorSpace(.sRGB)!
        let stored = AnnotationPalette.fill("yellow").usingColorSpace(.sRGB)!
        XCTAssertEqual(stored.redComponent, 1 - 0.43 * (1 - web.redComponent), accuracy: 0.001)
        for name in AnnotationPalette.names { XCTAssertEqual(AnnotationPalette.name(for: AnnotationPalette.fill(name)), name) }
        XCTAssertEqual(AnnotationPalette.name(for: AnnotationPalette.web("blue")), "blue")
    }

    @MainActor
    func testRenderReaderAndLibrary() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FOLIO_RENDER_PNG"] else { return }
        var kept: [NSWindow] = []
        defer { _ = kept }
        for dark in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let workspace = Workspace(libraryRoot: root)
            workspace.sample()
            let document = try XCTUnwrap(workspace.document)
            let page = try XCTUnwrap(document.page(at: 0))
            let selection = try XCTUnwrap(document.findString("Research begins with a question", withOptions: []).first)
            for (p, a) in PDFEditing.marks(for: selection, in: document, type: .highlight, color: AnnotationPalette.fill("yellow")) { p.addAnnotation(a) }
            _ = page
            workspace.showDocumentNavigation = true; workspace.inspector = true
            workspace.tool = .highlight
            workspace.revision += 1
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for reading in [true, false] {
                if !reading { workspace.showLibrary() }
                let view: AnyView = reading ? AnyView(ReaderView(workspace: workspace)) : AnyView(LibraryView(workspace: workspace, onAsk: { _ in }).background(FolioBackdrop()))
                let host = NSHostingView(rootView: view.frame(width: 1180, height: 760))
                host.appearance = appearance
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = appearance
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                for _ in 0..<20 { host.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 50_000_000) }
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(reading ? "reader" : "library")-\(dark ? "dark" : "light").png"))
                kept.append(window)
            }
        }
    }
}

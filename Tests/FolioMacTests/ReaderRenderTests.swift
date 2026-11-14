import XCTest
import PDFKit
import SwiftUI
import AppKit
import FolioCore
@testable import FolioMac

final class ReaderRenderTests: XCTestCase {
    func testZoomClampingAndRestore() {
        XCTAssertNil(ReaderZoom.restored(nil))
        XCTAssertNil(ReaderZoom.restored(0))
        XCTAssertNil(ReaderZoom.restored(0.1))
        XCTAssertNil(ReaderZoom.restored(.nan))
        XCTAssertNil(ReaderZoom.restored(.infinity))
        XCTAssertNil(ReaderZoom.restored(100))
        XCTAssertEqual(ReaderZoom.restored(1.5), 1.5)
        XCTAssertEqual(ReaderZoom.clamped(0), ReaderZoom.minimum)
        XCTAssertEqual(ReaderZoom.clamped(.nan), 1)
        XCTAssertEqual(ReaderZoom.clamped(50), ReaderZoom.maximum)
        XCTAssertEqual(ReaderZoom.clamped(2, lower: 0.1, upper: 100), 2)
    }

    func testAnnotationPaletteIsConsistent() {
        XCTAssertEqual(AnnotationPalette.names, ["yellow", "green", "blue", "pink"])
        XCTAssertEqual(AnnotationPalette.normalized("purple"), "yellow")
        let defaults = UserDefaults(suiteName: "folio-palette-\(UUID().uuidString)")!
        XCTAssertEqual(AnnotationPalette.stored(defaults), "yellow")
        AnnotationPalette.store("pink", defaults)
        XCTAssertEqual(AnnotationPalette.stored(defaults), "pink")
    }

    @MainActor
    func testWorkspaceColorMatchesPalette() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        for name in AnnotationPalette.names {
            workspace.markColor = name
            XCTAssertEqual(workspace.selectedColor, AnnotationPalette.fill(name))
        }
        workspace.markColor = "yellow"
    }

    @MainActor
    func testCorruptSavedZoomFallsBackToFitPage() async throws {
        try await assertVisible(corrupt: ReadingPosition(zoom: 0.01, fit: "custom"))
        try await assertVisible(corrupt: ReadingPosition(zoom: 1e9, fit: "custom"))
    }

    @MainActor
    func testReaderShowsPageWithFiniteScale() async throws { try await assertVisible(corrupt: nil) }

    @MainActor
    private func assertVisible(corrupt: ReadingPosition?) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        if let corrupt, let id = workspace.activeID {
            try ReadingPositionStore(root: root).set(corrupt, for: id)
            workspace.showLibrary()
            workspace.open(try XCTUnwrap(workspace.activePaper))
        }
        let host = NSHostingView(rootView: ReaderView(workspace: workspace).frame(width: 1000, height: 800))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        if ProcessInfo.processInfo.environment["FOLIO_RENDER_PNG"] != nil { workspace.tool = .highlight }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let pdf = try XCTUnwrap(workspace.pdfView)
        XCTAssertTrue(pdf.scaleFactor.isFinite && pdf.scaleFactor > 0.05, "scale \(pdf.scaleFactor)")
        XCTAssertFalse(pdf.visiblePages.isEmpty)
        XCTAssertGreaterThan(pdf.bounds.width, 300)
        XCTAssertEqual(workspace.reader.fit, .page)
        XCTAssertLessThan(pdf.scaleFactor, 1.2)
        if ProcessInfo.processInfo.environment["FOLIO_RENDER_PNG"] != nil {
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/folio-readerfix/view.png"))
        }
    }
}

import XCTest
import PDFKit
import SwiftUI
import AppKit
import FolioCore
@testable import FolioMac

final class WebStyleRenderTests: XCTestCase {
    func testHighlightColorsMatchPreviewAndSurvivePDFRoundTrip() throws {
        let expected: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("yellow", 250, 205, 90), ("green", 124, 200, 104),
            ("blue", 105, 176, 241), ("pink", 251, 92, 137)
        ]
        let document = PDFDocument()
        let page = PDFPage()
        document.insert(page, at: 0)
        for (name, r, g, b) in expected {
            let color = try XCTUnwrap(AnnotationPalette.fill(name).usingColorSpace(.sRGB))
            XCTAssertEqual(color.redComponent, r / 255, accuracy: 0.000001)
            XCTAssertEqual(color.greenComponent, g / 255, accuracy: 0.000001)
            XCTAssertEqual(color.blueComponent, b / 255, accuracy: 0.000001)
            XCTAssertEqual(color.alphaComponent, 1)
            XCTAssertEqual(AnnotationPalette.swatch(name), AnnotationPalette.fill(name))
            let annotation = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 100, height: 20),
                                           forType: .highlight, withProperties: nil)
            annotation.color = color
            page.addAnnotation(annotation)
        }
        let data = try XCTUnwrap(document.dataRepresentation())
        let reopened = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        for (annotation, expected) in zip(reopened.annotations, expected) {
            let color = try XCTUnwrap(annotation.color.usingColorSpace(.sRGB))
            XCTAssertEqual(color.redComponent, expected.1 / 255, accuracy: 0.00001)
            XCTAssertEqual(color.greenComponent, expected.2 / 255, accuracy: 0.00001)
            XCTAssertEqual(color.blueComponent, expected.3 / 255, accuracy: 0.00001)
            XCTAssertEqual(AnnotationPalette.name(for: color), expected.0)
        }
        // Existing managed PDFs keep their previous pale colors and remain recognizable.
        let oldYellow = NSColor(srgbRed: 1 - 0.43 * (1 - 246.0 / 255),
                                green: 1 - 0.43 * (1 - 216.0 / 255),
                                blue: 1 - 0.43 * (1 - 106.0 / 255), alpha: 1)
        XCTAssertEqual(AnnotationPalette.name(for: oldYellow), "yellow")
    }

    /// Guards legibility for the dense labels and active states, rather than view declarations.
    @MainActor
    func testThemeTextContrastInBothAppearances() throws {
        let pairs: [(String, Color, Color)] = [
            ("body", FolioTheme.ink, FolioTheme.card),
            ("secondary", FolioTheme.muted, FolioTheme.background),
            ("notes", FolioTheme.noteInk, FolioTheme.panelRight),
            ("sidebar", FolioTheme.rowInk, FolioTheme.panelLeft),
            ("selected row", FolioTheme.rowActiveInk, FolioTheme.rowActive),
            ("toolbar", FolioTheme.iconIdle, FolioTheme.strip),
            ("selected tool", FolioTheme.iconActiveInk, FolioTheme.iconActiveBg),
            ("badge", FolioTheme.badgeInk, FolioTheme.badge),
            ("primary action", FolioTheme.onAccent, FolioTheme.accent)
        ]
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                func luminance(_ color: Color) -> Double {
                    let rgb = NSColor(color).usingColorSpace(.sRGB)!
                    func linear(_ value: Double) -> Double {
                        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                    }
                    return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
                }
                for (label, foreground, background) in pairs {
                    let a = luminance(foreground), b = luminance(background)
                    XCTAssertGreaterThanOrEqual((max(a, b) + 0.05) / (min(a, b) + 0.05), 4.5,
                                                "\(label) in \(name.rawValue)")
                }
            }
        }
    }

    /// Opt-in visual fixtures use only generated PDFs and parsed, source-validated overviews.
    @MainActor
    func testRenderPaperGlance() async throws {
        guard let directory = ProcessInfo.processInfo.environment["FOLIO_RENDER_PNG"] else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let record = try XCTUnwrap(workspace.activePaper)
        let model = PaperAssistantModel()
        model.load(root: root, record: record)
        let paper = try XCTUnwrap(model.paper)
        let source = try XCTUnwrap(paper.passages.first)
        let available: [String: Any] = ["available": true, "label": "Find useful evidence in research papers",
                                      "explanation": "The synthetic fixture demonstrates a source-backed idea. Open its source to read the exact passage.", "sentence_ids": [source.id]]
        let missing: [String: Any] = ["available": false, "label": "", "explanation": "", "sentence_ids": []]
        var windows: [NSWindow] = []
        defer { for window in windows { window.orderOut(nil) } }
        for (name, width, dark, state) in [("wide", 920.0, false, "full"), ("narrow", 520.0, false, "full"),
                                           ("dark", 920.0, true, "full"), ("missing", 920.0, false, "missing"),
                                           ("empty", 520.0, false, "empty")] {
            if state == "empty" { model.snapshot?.overview = nil }
            else {
                let data = try JSONSerialization.data(withJSONObject: ["problem": available, "approach": available, "finding": state == "missing" ? missing : available])
                model.snapshot?.overview = try AssistantOverview.parse(String(decoding: data, as: UTF8.self), paper: paper, provider: .codex)
            }
            let host = NSHostingView(rootView: GlancePanel(workspace: workspace, model: model, paper: record)
                .padding(20).frame(width: width).preferredColorScheme(dark ? .dark : .light))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host; window.makeKeyAndOrderFront(nil)
            for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 50_000_000) }
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("glance-\(name).png"))
            if name == "wide" {
                try AssistantRepository(root: root, paperID: record.id, paper: paper).save(try XCTUnwrap(model.snapshot))
                let preview = URL(fileURLWithPath: directory).appendingPathComponent("library-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: root, to: preview)
                try preview.path.write(to: URL(fileURLWithPath: directory).appendingPathComponent("fixture-path.txt"), atomically: true, encoding: .utf8)
            }
            windows.append(window)
        }
    }

    /// Opt-in Ask layout fixtures. No provider calls, real papers or default library writes.
    @MainActor
    func testRenderAskPanel() async throws {
        guard let directory = ProcessInfo.processInfo.environment["FOLIO_RENDER_PNG"] else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        let record = try XCTUnwrap(workspace.activePaper)
        var windows: [NSWindow] = []
        defer { for window in windows { window.orderOut(nil) } }
        for (name, width, height, dark) in [("conversation", 405.0, 874.0, false), ("narrow", 320.0, 600.0, false),
                                          ("compact", 280.0, 480.0, false),
                                          ("dark", 405.0, 650.0, true), ("empty", 320.0, 600.0, false),
                                          ("streaming", 320.0, 600.0, false), ("passage", 320.0, 600.0, false)] {
            let model = PaperAssistantModel()
            model.load(root: root, record: record)
            if name != "empty" {
                model.threads?.append(question: "Hello", answer: """
                Hello! I'm the reading assistant for *this synthetic paper*. I can help with this paper.

                Here are some things I can do:
                - Explain the main idea and how it relates to earlier research.
                - Walk through the training method, including the assumptions and the evidence on [p. 1].
                - Summarize the experiments and their limitations.
                - Explain a passage, figure, table, or equation you select.

                What would you like to know?
                """, titleSource: "Hello")
            }
            if name == "streaming" {
                model.pendingQuestion = "Explain the method"
                model.streaming = "The method has three steps. First, define a clear question."
                model.busy = true
            }
            workspace.askRequest = name == "passage" ? AskRequest(selection: "A selected passage that wraps over several lines to check the attachment and composer stay visible together.", page: 1,
                                                                  prompt: "How does this relate to the main contribution? Please explain the assumptions and evidence.", autoSend: false) : nil
            let host = NSHostingView(rootView: AskPanel(workspace: workspace, model: model, paper: record)
                .frame(width: width, height: height).preferredColorScheme(dark ? .dark : .light))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.appearance = window.appearance
            window.contentView = host; window.makeKeyAndOrderFront(nil)
            for _ in 0..<8 { host.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 50_000_000) }
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("ask-\(name).png"))
            windows.append(window)
        }
    }

    /// Exercise opening and resizing within the actual reader split, not just an isolated Ask view.
    @MainActor
    func testRenderAskReaderResize() async throws {
        guard let directory = ProcessInfo.processInfo.environment["FOLIO_RENDER_PNG"] else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        workspace.sample()
        workspace.showDocumentNavigation = true
        workspace.inspector = false
        let host = NSHostingView(rootView: ReaderView(workspace: workspace).preferredColorScheme(.light))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 960, height: 640),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        for (name, width, height, open) in [("opened", 960.0, 640.0, true), ("wide", 1380.0, 880.0, true),
                                          ("resized", 960.0, 640.0, true), ("closed", 960.0, 640.0, false),
                                          ("reopened", 960.0, 640.0, true)] {
            workspace.panel = .ask; workspace.inspector = open
            window.setContentSize(CGSize(width: width, height: height))
            for _ in 0..<10 { host.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 50_000_000) }
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(workspace.pdfView).bounds.width, 350)
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("ask-reader-\(name).png"))
        }
    }

    @MainActor
    func testRenderReaderAndLibrary() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FOLIO_RENDER_PNG"] else { return }
        var kept: [NSWindow] = []
        defer { _ = kept }
        for (dark, reduced, increased, width, suffix) in [
            (false, false, false, 1180.0, "light"), (true, false, false, 1180.0, "dark"),
            (false, true, false, 1180.0, "light-solid"), (true, false, true, 1180.0, "dark-solid"),
            (false, false, false, 960.0, "light-narrow"), (true, false, false, 960.0, "dark-narrow")
        ] {
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
                let view = WorkspaceView(workspace: workspace)
                    .environment(\.folioOpaqueSurfaces, reduced || increased)
                    .preferredColorScheme(dark ? .dark : .light)
                let host = NSHostingView(rootView: view.frame(width: width, height: 760))
                host.appearance = appearance
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = appearance
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                for _ in 0..<20 { host.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 50_000_000) }
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(reading ? "reader" : "library")-\(suffix).png"))
                kept.append(window)
            }
        }
    }
}

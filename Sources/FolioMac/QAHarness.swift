import AppKit
import PDFKit
import SwiftUI
import FolioCore

/// Agent QA harness. Completely inert unless the `FOLIO_QA_DIR` environment variable is set at launch.
/// When active it listens for distributed notifications named `dev.folio.mac.qa` whose `object` is a command string,
/// runs them in order on the main actor through the app's normal Workspace/ReaderState APIs, and writes
/// `<FOLIO_QA_DIR>/ack.txt` ("<seq> ok <command>" or "<seq> error <msg>"). See scripts/qa.sh for the command list.
@MainActor
final class QAHarness {
    static var notificationName: Notification.Name {
        let dir = ProcessInfo.processInfo.environment["FOLIO_QA_DIR"] ?? "/tmp/folio-qa"
        return Notification.Name("dev.folio.mac.qa." + (dir as NSString).lastPathComponent)
    }
    /// Posted (object: "notes" | "highlights") for the notes inspector, whose tab is view-local state.
    static let rightTabName = Notification.Name("dev.folio.mac.qa.rightTab")
    private static var shared: QAHarness?

    /// Single additive entry point; does nothing when FOLIO_QA_DIR is unset.
    static func startIfRequested(_ workspace: Workspace) {
        guard shared == nil, let path = ProcessInfo.processInfo.environment["FOLIO_QA_DIR"], path.hasPrefix("/") else { return }
        shared = QAHarness(workspace: workspace, directory: URL(fileURLWithPath: path, isDirectory: true))
    }

    private let workspace: Workspace
    private let directory: URL
    private var queue: [String] = []
    private var running = false
    private var seq = 0
    private var observer: NSObjectProtocol?
    private var originalAppearance: String??

    private init(workspace: Workspace, directory: URL) {
        self.workspace = workspace; self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.notificationName, object: nil, queue: .main) { [weak self] note in
            guard let command = note.object as? String else { return }
            MainActor.assumeIsolated { self?.enqueue(command) }
        }
        try? "ready\n".write(to: directory.appendingPathComponent("ready.txt"), atomically: true, encoding: .utf8)
    }

    private struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }

    private func enqueue(_ command: String) {
        queue.append(command)
        guard !running else { return }
        running = true
        Task { @MainActor in
            while !queue.isEmpty {
                let command = queue.removeFirst()
                seq += 1
                let ack: String
                do { try await run(command); ack = "\(seq) ok \(command)" }
                catch let failure as Failure { ack = "\(seq) error \(failure.message)" }
                catch { ack = "\(seq) error \(error.localizedDescription)" }
                try? (ack + "\n").write(to: directory.appendingPathComponent("ack.txt"), atomically: true, encoding: .utf8)
                if command == "quit" { NSApp.terminate(nil) }
            }
            running = false
        }
    }

    private func settle(_ seconds: Double = 0.6) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain && $0.contentView != nil && !$0.isSheet }
    }

    // MARK: Commands

    private func run(_ command: String) async throws {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let name = parts.first else { throw Failure("empty command") }
        let args = Array(parts.dropFirst())
        func arg(_ i: Int) throws -> String { guard args.count > i else { throw Failure("\(name): missing argument") }; return args[i] }
        func int(_ i: Int) throws -> Int { guard let v = Int(try arg(i)) else { throw Failure("\(name): expected integer at \(i + 1)") }; return v }
        func flag(_ i: Int) throws -> Bool {
            switch try arg(i) { case "on": true; case "off": false; default: throw Failure("\(name): expected on|off") }
        }
        let reader = workspace.reader
        switch name {
        case "snapshot": try snapshot(try arg(0), after: await settle())
        case "open-sample":
            if workspace.document == nil || !workspace.reading { workspace.sample() }
            await settle(1.2)
            guard workspace.reading else { throw Failure("sample did not open") }
        case "library": workspace.navigate(to: .all)
        case "section":
            let map: [String: LibrarySection] = ["all": .all, "opened": .opened, "notes": .notes, "starred": .starred, "insights": .insights]
            guard let section = map[try arg(0)] else { throw Failure("unknown library section") }
            workspace.navigate(to: section)
        case "read-inspected":
            guard let paper = workspace.papers.first(where: { $0.id == workspace.insightsPaperID }) ?? workspace.activePaper else { throw Failure("no inspected paper") }
            workspace.open(paper)
        case "library-layout":
            let layout = try arg(0)
            guard ["list", "grid"].contains(layout) else { throw Failure("list|grid") }
            UserDefaults.standard.set(layout, forKey: "libraryLayout")
        case "tool":
            let map: [String: PDFTool] = ["select": .select, "highlight": .highlight, "underline": .underline, "text": .text, "note": .note, "eraser": .erase]
            guard let tool = map[try arg(0)] else { throw Failure("unknown tool") }
            workspace.chooseTool(tool)
        case "color":
            let c = try arg(0)
            guard AnnotationPalette.names.contains(c) else { throw Failure("unknown color") }
            workspace.markColor = c
        case "mark-line":
            let kind = try arg(0)
            guard kind == "highlight" || kind == "underline" else { throw Failure("mark-line: highlight|underline") }
            let page = try int(1), index = try int(2)
            guard let doc = workspace.document, page >= 1, page <= doc.pageCount, let pdfPage = doc.page(at: page - 1) else { throw Failure("bad page") }
            let lines = (pdfPage.selection(for: pdfPage.bounds(for: .cropBox))?.selectionsByLine() ?? [])
                .filter { !($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard index >= 0, index < lines.count else { throw Failure("line \(index) out of range (\(lines.count) text lines)") }
            workspace.go(to: page)
            workspace.pdfView?.setCurrentSelection(lines[index], animate: false)
            workspace.markSelection(kind == "highlight" ? .highlight : .underline)
        case "add-text":
            let page = try int(0)
            guard let x = Double(try arg(1)), let y = Double(try arg(2)), args.count > 3 else { throw Failure("add-text <page> <x> <y> <text>") }
            guard let doc = workspace.document, page >= 1, page <= doc.pageCount, let pdfPage = doc.page(at: page - 1) else { throw Failure("bad page") }
            workspace.go(to: page)
            workspace.beginText(on: pdfPage, at: CGPoint(x: x, y: y))
            await settle(0.4)
            guard let inline = workspace.inlineText else { throw Failure("inline editor did not start") }
            inline.textView.insertText(args.dropFirst(3).joined(separator: " "), replacementRange: NSRange(location: 0, length: 0))
        case "commit-text":
            if let inline = workspace.inlineText { inline.commit() } else { _ = workspace.finishEditorIfNeeded() }
        case "select-annotation":
            let page = try int(0), index = try int(1)
            guard let doc = workspace.document, page >= 1, page <= doc.pageCount, let pdfPage = doc.page(at: page - 1) else { throw Failure("bad page") }
            let annotations = pdfPage.annotations
            guard index >= 0, index < annotations.count else { throw Failure("annotation \(index) out of range (\(annotations.count))") }
            workspace.select(annotations[index])
            workspace.pdfView?.needsDisplay = true
        case "rotate":
            switch try arg(0) { case "left": reader.rotate(by: -90); case "right": reader.rotate(by: 90); default: throw Failure("left|right") }
        case "zoom":
            switch try arg(0) {
            case "in": reader.zoomIn(); case "out": reader.zoomOut()
            case "fit-width": reader.setFit(.width); case "fit-page": reader.setFit(.page); case "actual": reader.setFit(.actual)
            default: throw Failure("in|out|fit-width|fit-page|actual")
            }
        case "page": workspace.go(to: try int(0))
        case "layout":
            let map: [String: ReaderLayout] = ["single": .single, "continuous": .singleContinuous, "two": .two, "two-continuous": .twoContinuous]
            guard let layout = map[try arg(0)] else { throw Failure("single|continuous|two|two-continuous") }
            reader.setLayout(layout)
        case "left-sidebar": workspace.showDocumentNavigation = try flag(0)
        case "right-sidebar": workspace.inspector = try flag(0)
        case "right-tab":
            let tab = try arg(0)
            guard tab == "notes" || tab == "highlights" else { throw Failure("notes|highlights") }
            NotificationCenter.default.post(name: Self.rightTabName, object: tab)
        case "search":
            let text = args.joined(separator: " ")
            workspace.showFind = !text.isEmpty
            reader.query = text
            await settle(0.5)
        case "appearance":
            let mode = try arg(0)
            guard ["light", "dark", "system"].contains(mode) else { throw Failure("light|dark|system") }
            if originalAppearance == nil { originalAppearance = .some(UserDefaults.standard.string(forKey: "appearance")) }
            UserDefaults.standard.set(mode, forKey: "appearance") // drives the app's preferredColorScheme
            NSApp.appearance = mode == "system" ? nil : NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        case "window":
            guard let w = Double(try arg(0)), let h = Double(try arg(1)), let window = mainWindow else { throw Failure("window <w> <h>") }
            window.setContentSize(NSSize(width: w, height: h))
        case "assistant": workspace.present(.assistant)
        case "reviews": workspace.present(.reviews)
        case "concept-map": workspace.present(.concepts)
        case "overview": workspace.present(.overview)
        case "select-line":
            let page = try int(0), index = try int(1)
            guard let doc = workspace.document, page >= 1, page <= doc.pageCount, let pdfPage = doc.page(at: page - 1) else { throw Failure("bad page") }
            let lines = (pdfPage.selection(for: pdfPage.bounds(for: .cropBox))?.selectionsByLine() ?? [])
                .filter { !($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard index >= 0, index < lines.count else { throw Failure("line \(index) out of range (\(lines.count) text lines)") }
            workspace.go(to: page)
            workspace.pdfView?.setCurrentSelection(lines[index], animate: false)
        case "settings-shot":   // settings-shot <name> <codex|claude>: open Settings, capture its window
            let name = try arg(0)
            guard name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw Failure("bad name") }
            UserDefaults.standard.set(try arg(1) == "claude" ? AssistantProvider.claude.rawValue : AssistantProvider.codex.rawValue, forKey: "folio.assistant.provider")
            if let appMenu = NSApp.mainMenu?.items.first?.submenu,
               let index = appMenu.items.firstIndex(where: { $0.keyEquivalent == "," }) { appMenu.performActionForItem(at: index) }
            await settle(1.0)
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0 !== mainWindow && !$0.isSheet && $0.contentView != nil }) else { throw Failure("settings window not found") }
            if let scroll = window.contentView?.firstScrollView { scroll.documentView?.scroll(NSPoint(x: 0, y: scroll.documentView?.bounds.height ?? 0)) }
            await settle(0.3)
            guard let image = Self.windowListImage(window), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw Failure("capture failed") }
            try data.write(to: directory.appendingPathComponent("\(name).png"))
        case "ask-selection": workspace.askAboutSelection(explain: false)   // prefill only; never sends
        case "close-sheet":
            if workspace.showArxivImport { workspace.showArxivImport = false }
            else if let window = NSApp.windows.first(where: { $0.attachedSheet != nil }), let sheet = window.attachedSheet { window.endSheet(sheet) }
            else { throw Failure("no sheet open") }
        case "undo": workspace.undo()
        case "redo": workspace.redo()
        case "quit":
            if let original = originalAppearance {
                if let value = original { UserDefaults.standard.set(value, forKey: "appearance") } else { UserDefaults.standard.removeObject(forKey: "appearance") }
            }
        default: throw Failure("unknown command '\(name)'")
        }
        if name != "snapshot" { await settle(0.3) }
    }

    // MARK: Snapshot

    private func snapshot(_ name: String, after _: Void) throws {
        guard name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { throw Failure("bad snapshot name") }
        guard let window = mainWindow, let content = window.contentView else { throw Failure("no window") }
        let scale = window.backingScaleFactor
        var method = "cgwindow"
        var image = Self.windowListImage(window)
        if image == nil || Self.isBlank(image!) {
            method = "cacheDisplay"
            let frameView = content.superview ?? content
            guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { throw Failure("no bitmap rep") }
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            if let pdfView = workspace.pdfView { Self.drawPages(of: pdfView, in: frameView, into: rep, scale: scale) }
            image = rep.cgImage
        }
        guard let cg = image else { throw Failure("capture failed") }
        guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw Failure("png encode failed") }
        try data.write(to: directory.appendingPathComponent("\(name).png"))
        // Sheets are separate windows; capture the frontmost attached sheet beside the main image.
        var sheet = window.attachedSheet ?? NSApp.windows.first { $0.isSheet && $0.isVisible }
        while let nested = sheet?.attachedSheet { sheet = nested }
        if let sheet {
            var sheetImage = Self.windowListImage(sheet)
            if sheetImage == nil || Self.isBlank(sheetImage!), let view = sheet.contentView?.superview ?? sheet.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep); sheetImage = rep.cgImage
            }
            if let sheetImage, let sheetData = NSBitmapImageRep(cgImage: sheetImage).representation(using: .png, properties: [:]) {
                try sheetData.write(to: directory.appendingPathComponent("\(name)-sheet.png"))
            }
        }
        try? "\(name) \(method) \(cg.width)x\(cg.height)\n".write(to: directory.appendingPathComponent("snapshot.log"), atomically: true, encoding: .utf8)
    }

    /// CGWindowListCreateImage is unavailable to Swift on new SDKs, so it is looked up dynamically.
    private static func windowListImage(_ window: NSWindow) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        let optionIncludingWindow: UInt32 = 1 << 3, boundsIgnoreFraming: UInt32 = 1 << 0
        return fn(.null, optionIncludingWindow, UInt32(window.windowNumber), boundsIgnoreFraming)?.takeRetainedValue()
    }

    private static func isBlank(_ image: CGImage) -> Bool {
        let w = 24, h = 24
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let first = Array(pixels[0..<4])
        for i in stride(from: 0, to: pixels.count, by: 4) where Array(pixels[i..<i + 4]) != first { return false }
        return true
    }

    /// cacheDisplay can leave PDFView's page content blank; draw visible pages manually at their on-screen rects.
    private static func drawPages(of pdfView: PDFView, in frameView: NSView, into rep: NSBitmapImageRep, scale: CGFloat) {
        guard !frameView.isFlipped, let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return }
        for page in pdfView.visiblePages where page.rotation == 0 {
            let box = page.bounds(for: pdfView.displayBox)
            let rect = frameView.convert(pdfView.convert(box, from: page), from: pdfView)
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: rect.minX, y: rect.minY)
            ctx.scaleBy(x: rect.width / box.width, y: rect.height / box.height)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            page.draw(with: pdfView.displayBox, to: ctx)
            ctx.restoreGState()
        }
    }
}

private extension NSView {
    var firstScrollView: NSScrollView? {
        if let scroll = self as? NSScrollView { return scroll }
        for child in subviews { if let found = child.firstScrollView { return found } }
        return nil
    }
}

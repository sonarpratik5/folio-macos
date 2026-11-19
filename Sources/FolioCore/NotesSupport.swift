import AppKit
import PDFKit

/// Local, per-paper storage for images attached to notes. Files live beside the managed library
/// copies and are referenced from the note annotation by file name only.
public struct NoteImageStore {
    public let root: URL
    public init(root: URL) { self.root = root }

    public func directory(for paper: UUID) -> URL {
        root.appendingPathComponent("NoteImages", isDirectory: true).appendingPathComponent(paper.uuidString, isDirectory: true)
    }
    /// Only names this store generated are valid; anything else (including paths) is rejected.
    public static func isValid(_ name: String) -> Bool {
        guard name.hasSuffix(".png") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }
    public func save(_ png: Data, paper: UUID) throws -> String {
        let folder = directory(for: paper)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".png"
        try png.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }
    public func url(_ name: String, paper: UUID) -> URL? {
        Self.isValid(name) ? directory(for: paper).appendingPathComponent(name) : nil
    }
    public func data(_ name: String, paper: UUID) -> Data? { url(name, paper: paper).flatMap { try? Data(contentsOf: $0) } }
    public func remove(_ name: String, paper: UUID) {
        if let url = url(name, paper: paper) { try? FileManager.default.removeItem(at: url) }
    }

    public static func png(from image: NSImage, maxPixels: CGFloat = 1600) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let longest = CGFloat(max(bitmap.pixelsWide, bitmap.pixelsHigh))
        var source = bitmap
        if longest > maxPixels, let cg = bitmap.cgImage {
            let scale = maxPixels / longest
            let w = max(1, Int(CGFloat(bitmap.pixelsWide) * scale)), h = max(1, Int(CGFloat(bitmap.pixelsHigh) * scale))
            guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let scaled = context.makeImage() else { return nil }
            source = NSBitmapImageRep(cgImage: scaled)
        }
        return source.representation(using: .png, properties: [:])
    }
}

/// Unsaved note text, autosaved so it survives a quit or crash.
public struct NoteDraftRecord: Codable, Equatable {
    public var page: Int
    public var x: Double, y: Double, width: Double, height: Double
    public var isFreeText: Bool
    public var text: String
    public var quote: String
    public var images: [String]
    public init(page: Int, bounds: CGRect, isFreeText: Bool, text: String, quote: String, images: [String] = []) {
        self.page = page; x = bounds.minX; y = bounds.minY; width = bounds.width; height = bounds.height
        self.isFreeText = isFreeText; self.text = text; self.quote = quote; self.images = images
    }
    public var bounds: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

public struct NoteDraftStore {
    public let root: URL
    public init(root: URL) { self.root = root }
    private func file(_ paper: UUID) -> URL {
        root.appendingPathComponent("Drafts", isDirectory: true).appendingPathComponent(paper.uuidString + ".json")
    }
    public func save(_ draft: NoteDraftRecord, paper: UUID) {
        let url = file(paper)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(draft) { try? data.write(to: url, options: .atomic) }
    }
    public func load(paper: UUID) -> NoteDraftRecord? {
        guard let data = try? Data(contentsOf: file(paper)),
              let draft = try? JSONDecoder().decode(NoteDraftRecord.self, from: data),
              draft.page > 0, [draft.x, draft.y, draft.width, draft.height].allSatisfy(\.isFinite),
              (!draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               (!draft.isFreeText && draft.images.contains(where: NoteImageStore.isValid))) else { return nil }
        return draft
    }
    public func clear(paper: UUID) { try? FileManager.default.removeItem(at: file(paper)) }
}

/// Blank, lightly ruled pages for typed notes. The page is a normal PDF page, so existing
/// text tools, undo and export work on it unchanged.
public enum WritingPages {
    public static func blankPage(size: CGSize) -> PDFPage? {
        guard size.width.isFinite, size.height.isFinite, size.width >= 100, size.height >= 100 else { return nil }
        let bytes = NSMutableData()
        guard let consumer = CGDataConsumer(data: bytes) else { return nil }
        var box = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
        context.setStrokeColor(CGColor(srgbRed: 0.78, green: 0.84, blue: 0.80, alpha: 1)); context.setLineWidth(0.5)
        var y = size.height - 72
        while y > 54 { context.move(to: CGPoint(x: 54, y: y)); context.addLine(to: CGPoint(x: size.width - 54, y: y)); y -= 28 }
        context.strokePath()
        context.endPDFPage(); context.closePDF()
        return PDFDocument(data: bytes as Data)?.page(at: 0)
    }
}

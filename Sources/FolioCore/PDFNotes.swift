import Foundation
import AppKit
import PDFKit

public struct PaperNote: Identifiable {
    public let id: String
    public let page: Int
    public let body: String
    public let annotation: PDFAnnotation
    public var color: NSColor { annotation.color }
    public var quote: String { annotation.value(forAnnotationKey: PDFEditing.quoteKey) as? String ?? "" }
    public var images: [String] { PDFNotes.images(of: annotation) }
}

public enum PDFNotes {
    public static let imagesKey = PDFAnnotationKey(rawValue: "FolioNoteImages")
    public static func images(of annotation: PDFAnnotation) -> [String] {
        ((annotation.value(forAnnotationKey: imagesKey) as? String) ?? "").split(separator: ",").map(String.init).filter(NoteImageStore.isValid)
    }
    /// Case-insensitive match against note text, quote and page; nil color means any.
    public static func filter(_ notes: [PaperNote], query: String, color: NSColor? = nil) -> [PaperNote] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { note in
            (q.isEmpty || note.body.localizedCaseInsensitiveContains(q) || note.quote.localizedCaseInsensitiveContains(q) || "page \(note.page)".localizedCaseInsensitiveContains(q))
                && (color.map { sameHue($0, note.color) } ?? true)
        }
    }
    static func sameHue(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a = a.usingColorSpace(.deviceRGB), let b = b.usingColorSpace(.deviceRGB) else { return false }
        return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) < 0.05
    }
    public static func grouped(_ notes: [PaperNote]) -> [(page: Int, notes: [PaperNote])] {
        Dictionary(grouping: notes, by: \.page).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
    /// Notes are written comments; bare highlights and other annotation kinds stay out.
    public static func read(from document: PDFDocument) -> [PaperNote] {
        (0..<document.pageCount).flatMap { index -> [PaperNote] in
            guard let page = document.page(at: index) else { return [] }
            return page.annotations.enumerated().compactMap { offset, annotation in
                guard annotation.type == "Text",
                      let text = annotation.contents?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                return PaperNote(id: "\(index)-\(offset)", page: index + 1, body: text, annotation: annotation)
            }
        }
    }
}

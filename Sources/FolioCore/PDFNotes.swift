import Foundation
import PDFKit

public struct PaperNote: Identifiable {
    public let id: String
    public let page: Int
    public let body: String
    public let annotation: PDFAnnotation
}

public enum PDFNotes {
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

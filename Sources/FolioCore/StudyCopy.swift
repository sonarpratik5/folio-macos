import AppKit
import PDFKit
import CoreText

/// Export augments a detached copy; imported pages and the live document are never reconstructed.
public enum StudyCopy {
    public static let generatedKey = PDFAnnotationKey(rawValue: "FolioGeneratedSheet")
    public static let writingKey = PDFAnnotationKey(rawValue: "FolioWritingBelow")
    public static let embeddedImagesKey = PDFAnnotationKey(rawValue: "FolioEmbeddedNoteImages")

    public static func embeddedImages(in annotation: PDFAnnotation) -> [String: String] {
        guard let raw = annotation.value(forAnnotationKey: embeddedImagesKey) as? String, raw.utf8.count <= 100_000_000,
              let data = raw.data(using: .utf8), let images = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return images.filter { NoteImageStore.isValid($0.key) && $0.value.utf8.count <= 28_000_000 }
    }

    public static func writing(on page: PDFPage) -> PDFAnnotation? {
        page.annotations.first { ($0.value(forAnnotationKey: writingKey) as? String) == "1" }
    }
    public static func continuationPages(text: String, size: CGSize, title: String) -> [PDFPage] {
        guard size.width >= 150, size.height >= 180, size.width.isFinite, size.height.isFinite else { return [] }
        let body = NSAttributedString(string: title + "\n\n" + text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black])
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        let bytes = NSMutableData()
        guard let consumer = CGDataConsumer(data: bytes) else { return [] }
        var box = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return [] }
        var offset = 0
        while offset < body.length {
            let path = CGPath(rect: box.insetBy(dx: 45, dy: 50), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            offset += visible.length
        }
        context.closePDF()
        guard offset == body.length, let pdf = PDFDocument(data: bytes as Data) else { return [] }
        return (0..<pdf.pageCount).compactMap { pdf.page(at: $0) }
    }
    public static func export(_ document: PDFDocument, study: Bool, imageData: (String) -> Data?) throws -> Data {
        guard let original = document.dataRepresentation(), let copy = PDFDocument(data: original) else { throw LibraryRepository.RepositoryError.encodingFailed }
        if study {
            for index in (0..<copy.pageCount).reversed() {
                if copy.page(at: index)?.annotations.contains(where: { ($0.value(forAnnotationKey: generatedKey) as? String) == "writing" }) == true { copy.removePage(at: index) }
            }
        }
        // Work backwards so all source page numbers continue to refer to the original document.
        for index in (0..<copy.pageCount).reversed() {
            guard let page = copy.page(at: index) else { continue }
            let size = page.bounds(for: .mediaBox).size
            var additions: [PDFPage] = []
            if study, let text = writing(on: page)?.contents, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let sheets = continuationPages(text: text, size: CGSize(width: max(300, size.width), height: max(400, size.height)), title: "Writing below page \(index + 1)")
                guard !sheets.isEmpty else { throw AssistantError.message("The writing continuation could not be typeset. Export was stopped to preserve your writing.") }
                for sheet in sheets {
                    let marker = PDFAnnotation(bounds: CGRect(x: 1, y: 1, width: 1, height: 1), forType: .text, withProperties: nil)
                    marker.setValue("writing", forAnnotationKey: generatedKey); marker.shouldDisplay = false; marker.shouldPrint = false
                    sheet.addAnnotation(marker)
                }
                additions += sheets
            }
            for annotation in page.annotations {
                var embedded: [String: String] = [:]
                let stored = embeddedImages(in: annotation)
                for name in PDFNotes.images(of: annotation) {
                    let existing = stored[name].flatMap { Data(base64Encoded: $0) }
                    guard let data = imageData(name) ?? existing, data.count <= 20_000_000, let image = NSImage(data: data), let imagePage = PDFPage(image: image) else {
                        throw AssistantError.message("A note image is missing or unreadable. Export was stopped so attachments are not silently lost.")
                    }
                    embedded[name] = data.base64EncodedString()
                    if existing == nil { additions.append(imagePage) }
                }
                if !embedded.isEmpty {
                    let encoded = try JSONEncoder().encode(embedded)
                    guard encoded.count <= 100_000_000 else { throw AssistantError.message("This note has too many image attachments to export together.") }
                    annotation.setValue(String(data: encoded, encoding: .utf8)!, forAnnotationKey: embeddedImagesKey)
                }
            }
            for (offset, addition) in additions.enumerated() { copy.insert(addition, at: index + 1 + offset) }
        }
        guard let data = copy.dataRepresentation() else { throw LibraryRepository.RepositoryError.encodingFailed }
        return data
    }
}

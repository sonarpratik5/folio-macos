import Foundation
import PDFKit

/// Owns managed copies only. Source URLs are used for import, never overwritten.
public final class LibraryRepository {
    public enum RepositoryError: LocalizedError {
        case invalidPDF, unsupportedSchema, invalidRecord, encodingFailed

        public var errorDescription: String? {
            switch self {
            case .invalidPDF: "Choose an unlocked PDF with at least one page."
            case .unsupportedSchema: "This library was made by a newer Folio. Its files were left untouched."
            case .invalidRecord: "The library contains an invalid record. Its files were left untouched."
            case .encodingFailed: "Folio could not encode this PDF. Your previous copy was kept."
            }
        }
    }

    public let root: URL
    private let fileManager: FileManager
    private var manifestURL: URL { root.appendingPathComponent("library.json") }

    public init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        self.fileManager = fileManager
        try fileManager.createDirectory(at: root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
    }

    public func documentURL(for id: UUID) -> URL {
        root.appendingPathComponent("Documents").appendingPathComponent(id.uuidString).appendingPathExtension("pdf")
    }

    public func load() throws -> [PaperRecord] {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: manifestURL))
        guard snapshot.schemaVersion == 1 else { throw RepositoryError.unsupportedSchema }
        guard Set(snapshot.papers.map(\.id)).count == snapshot.papers.count,
              snapshot.papers.allSatisfy({ paper in paper.pageCount > 0 && (1...paper.pageCount).contains(paper.currentPage)
                  && paper.starredPages.allSatisfy { (1...paper.pageCount).contains($0) } }) else {
            throw RepositoryError.invalidRecord
        }
        return snapshot.papers
    }

    public func save(_ papers: [PaperRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(LibrarySnapshot(papers: papers)).write(to: manifestURL, options: .atomic)
    }

    public func importPDF(from source: URL, existing: [PaperRecord]) throws -> PaperRecord {
        guard let document = PDFDocument(url: source), !document.isLocked, document.pageCount > 0 else {
            throw RepositoryError.invalidPDF
        }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let record = PaperRecord(title: title?.isEmpty == false ? title! : source.deletingPathExtension().lastPathComponent,
                                 pageCount: document.pageCount)
        let destination = documentURL(for: record.id)
        try fileManager.copyItem(at: source, to: destination)
        do { try save(existing + [record]) }
        catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        return record
    }

    public func saveDocument(_ document: PDFDocument, for id: UUID) throws {
        guard let data = document.dataRepresentation() else { throw RepositoryError.encodingFailed }
        try data.write(to: documentURL(for: id), options: .atomic)
    }
}

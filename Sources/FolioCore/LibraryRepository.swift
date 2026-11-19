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

    // Injectable file boundary for deterministic failure/recovery tests.
    var writeAtomically: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }

    struct StructureRollback: Codable {
        let paperID: UUID
        let document: Data
        let manifest: Data
    }
    private var rollbackURL: URL { root.appendingPathComponent("structure-rollback.json") }

    public let root: URL
    private let fileManager: FileManager
    private var manifestURL: URL { root.appendingPathComponent("library.json") }

    public init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        self.fileManager = fileManager
        try fileManager.createDirectory(at: root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try recoverStructureIfNeeded()
    }

    public func documentURL(for id: UUID) -> URL {
        root.appendingPathComponent("Documents").appendingPathComponent(id.uuidString).appendingPathExtension("pdf")
    }

    /// Resolve existing parent links even for a new filename. Compare path components so
    /// similarly named sibling directories remain valid export destinations.
    public func allowsExport(to destination: URL) -> Bool {
        guard destination.isFileURL else { return false }
        let rootParts = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var ancestor = destination.standardizedFileURL
        var missing: [String] = []
        while !fileManager.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missing.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in missing.reversed() { resolved.appendPathComponent(component) }
        let destinationParts = resolved.pathComponents
        return !destinationParts.starts(with: rootParts)
    }

    public func load() throws -> [PaperRecord] {
        try recoverStructureIfNeeded()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: manifestURL))
        try validate(snapshot)
        return snapshot.papers
    }

    public func loadFolders() throws -> [String] {
        try recoverStructureIfNeeded()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        return try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: manifestURL)).folders ?? []
    }

    public func save(_ papers: [PaperRecord], folders: [String]? = nil) throws {
        try recoverStructureIfNeeded()
        let data = try manifestData(papers, folders: try folders ?? loadFolders())
        try writeAtomically(data, manifestURL)
    }

    private func validate(_ snapshot: LibrarySnapshot) throws {
        guard snapshot.schemaVersion == 1 else { throw RepositoryError.unsupportedSchema }
        guard Set(snapshot.papers.map(\.id)).count == snapshot.papers.count,
              snapshot.papers.allSatisfy({ paper in paper.pageCount > 0 && (1...paper.pageCount).contains(paper.currentPage)
                  && paper.starredPages.allSatisfy { (1...paper.pageCount).contains($0) } }) else {
            throw RepositoryError.invalidRecord
        }
    }

    private func manifestData(_ papers: [PaperRecord], folders: [String]) throws -> Data {
        let snapshot = LibrarySnapshot(papers: papers, folders: folders)
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// PDF and metadata form one recoverable structural edit. The rollback journal is
    /// removed only after both replacements succeed; an interrupted edit rolls back on open.
    public func saveStructure(_ document: PDFDocument, for id: UUID, papers: [PaperRecord]) throws {
        try recoverStructureIfNeeded()
        guard let record = papers.first(where: { $0.id == id }), record.pageCount == document.pageCount,
              !document.isLocked, let data = document.dataRepresentation() else { throw RepositoryError.invalidRecord }
        let manifest = try manifestData(papers, folders: loadFolders())
        let rollback = StructureRollback(paperID: id, document: try Data(contentsOf: documentURL(for: id)),
                                         manifest: try Data(contentsOf: manifestURL))
        // Validate the recovery payload before allowing any managed-file replacement.
        let prior = try JSONDecoder().decode(LibrarySnapshot.self, from: rollback.manifest)
        try validate(prior)
        guard let oldRecord = prior.papers.first(where: { $0.id == id }),
              let oldDocument = PDFDocument(data: rollback.document), !oldDocument.isLocked,
              oldDocument.pageCount == oldRecord.pageCount else { throw RepositoryError.invalidRecord }
        try writeAtomically(JSONEncoder().encode(rollback), rollbackURL)
        do {
            try writeAtomically(data, documentURL(for: id))
            try writeAtomically(manifest, manifestURL)
            try fileManager.removeItem(at: rollbackURL)
        } catch {
            // If restoration itself fails, leave the journal and fail closed on future access.
            try recoverStructureIfNeeded()
            throw error
        }
    }

    private func recoverStructureIfNeeded() throws {
        guard fileManager.fileExists(atPath: rollbackURL.path) else { return }
        let rollback = try JSONDecoder().decode(StructureRollback.self, from: Data(contentsOf: rollbackURL))
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: rollback.manifest)
        try validate(snapshot)
        guard let record = snapshot.papers.first(where: { $0.id == rollback.paperID }),
              let document = PDFDocument(data: rollback.document), !document.isLocked,
              record.pageCount == document.pageCount else { throw RepositoryError.invalidRecord }
        try writeAtomically(rollback.document, documentURL(for: rollback.paperID))
        try writeAtomically(rollback.manifest, manifestURL)
        try fileManager.removeItem(at: rollbackURL)
    }

    public func importPDF(from source: URL, existing: [PaperRecord], title overrideTitle: String? = nil, folderPath: String? = nil) throws -> PaperRecord {
        guard let document = PDFDocument(url: source), !document.isLocked, document.pageCount > 0 else {
            throw RepositoryError.invalidPDF
        }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = overrideTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        var record = PaperRecord(title: chosen?.isEmpty == false ? chosen!
                                    : title?.isEmpty == false ? title! : source.deletingPathExtension().lastPathComponent,
                                 pageCount: document.pageCount, author: author?.isEmpty == false ? author : nil)
        record.folderPath = folderPath
        record.sourcePath = source.standardizedFileURL.path
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
        try recoverStructureIfNeeded()
        guard let data = document.dataRepresentation() else { throw RepositoryError.encodingFailed }
        try writeAtomically(data, documentURL(for: id))
    }

    /// Removes the record and its managed copy. The manifest is saved first so a failure never orphans a record.
    public func remove(_ id: UUID, from existing: [PaperRecord]) throws -> [PaperRecord] {
        let next = existing.filter { $0.id != id }
        try save(next)
        try? fileManager.removeItem(at: documentURL(for: id))
        return next
    }
}

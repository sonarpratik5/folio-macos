import Foundation

public struct PaperRecord: Codable, Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public let pageCount: Int
    public var currentPage: Int
    public var starredPages: Set<Int>
    public var lastOpened: Date
    /// Optional so libraries written before these fields existed still decode.
    public var addedAt: Date?
    public var author: String?

    public init(id: UUID = UUID(), title: String, pageCount: Int, author: String? = nil) {
        self.id = id
        self.title = title
        self.pageCount = pageCount
        self.currentPage = 1
        self.starredPages = []
        self.lastOpened = Date()
        self.addedAt = Date()
        self.author = author
    }
}

public struct LibrarySnapshot: Codable {
    public let schemaVersion: Int
    public var papers: [PaperRecord]

    public init(papers: [PaperRecord] = []) {
        schemaVersion = 1
        self.papers = papers
    }
}

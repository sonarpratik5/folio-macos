import Foundation

public struct PaperRecord: Codable, Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public let pageCount: Int
    public var currentPage: Int
    public var starredPages: Set<Int>
    public var lastOpened: Date

    public init(id: UUID = UUID(), title: String, pageCount: Int) {
        self.id = id
        self.title = title
        self.pageCount = pageCount
        self.currentPage = 1
        self.starredPages = []
        self.lastOpened = Date()
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

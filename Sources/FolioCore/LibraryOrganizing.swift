import Foundation

public enum LibrarySortOrder: String, CaseIterable, Identifiable, Sendable {
    case recentlyOpened = "Recently opened", added = "Date added", title = "Title", author = "Author"
    public var id: String { rawValue }
}

public enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", starred = "Starred", withNotes = "With notes", unread = "Unread"
    public var id: String { rawValue }
}

public enum LibraryOrganizer {
    /// `noteCounts` supplies the per-paper written-note count (read from the PDF by the caller).
    public static func apply(_ papers: [PaperRecord], query: String = "", filter: LibraryFilter = .all,
                             order: LibrarySortOrder, noteCounts: [UUID: Int] = [:],
                             noteText: [UUID: String] = [:]) -> [PaperRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return papers.filter { paper in
            let matches = q.isEmpty || paper.title.localizedCaseInsensitiveContains(q)
                || (paper.author?.localizedCaseInsensitiveContains(q) ?? false)
                || (noteText[paper.id]?.localizedCaseInsensitiveContains(q) ?? false)
            guard matches else { return false }
            switch filter {
            case .all: return true
            case .starred: return !paper.starredPages.isEmpty
            case .withNotes: return (noteCounts[paper.id] ?? 0) > 0
            case .unread: return paper.currentPage <= 1
            }
        }.sorted { a, b in
            func byTitle() -> Bool { a.title.localizedStandardCompare(b.title) == .orderedAscending }
            switch order {
            case .recentlyOpened: return a.lastOpened == b.lastOpened ? byTitle() : a.lastOpened > b.lastOpened
            case .added:
                let (x, y) = (a.addedAt ?? a.lastOpened, b.addedAt ?? b.lastOpened)
                return x == y ? byTitle() : x > y
            case .title: return byTitle()
            case .author:
                switch (a.author, b.author) {
                case let (x?, y?):
                    let c = x.localizedStandardCompare(y)
                    return c == .orderedSame ? byTitle() : c == .orderedAscending
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return byTitle()
                }
            }
        }
    }
}

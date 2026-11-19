import Foundation

public struct ConversationEntry: Identifiable, Sendable {
    public let id: UUID
    public let paperID: UUID
    public let paperTitle: String
    public let title: String
    public let content: String
    public let updatedAt: Date
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || title.localizedCaseInsensitiveContains(query) || paperTitle.localizedCaseInsensitiveContains(query) || content.localizedCaseInsensitiveContains(query)
    }
}

public enum ConversationIndex {
    /// Local read-only scan of bounded chat files, independent of PDF extraction or provider configuration.
    public static func load(root: URL, papers: [(UUID, String)]) -> (entries: [ConversationEntry], failures: Int) {
        var entries: [ConversationEntry] = []; var failed = 0
        for (id, title) in papers {
            if Task.isCancelled { break }
            let threadURL = root.appendingPathComponent("Assistant/\(id.uuidString).threads.json")
            let legacyURL = root.appendingPathComponent("Assistant/\(id.uuidString).json")
            let hasThreads = FileManager.default.fileExists(atPath: threadURL.path)
            let url = hasThreads ? threadURL : legacyURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 8_000_000 else { throw AssistantError.invalidData }
                let data = try Data(contentsOf: url)
                let threads: AssistantThreads
                if hasThreads {
                    let header = try JSONDecoder().decode(AssistantThreads.self, from: data)
                    threads = try AssistantThreadRepository(root: root, paperID: id, fingerprint: header.fingerprint).load(legacyTurns: [])
                } else {
                    let legacy = try JSONDecoder().decode(AssistantSnapshot.self, from: data)
                    guard legacy.paperID == id, legacy.schemaVersion == 1 else { throw AssistantError.invalidData }
                    threads = try AssistantThreadRepository(root: root, paperID: id, fingerprint: legacy.fingerprint).load(legacyTurns: legacy.turns)
                }
                entries += threads.threads.filter { !$0.turns.isEmpty }.map {
                    ConversationEntry(id: $0.id, paperID: id, paperTitle: title, title: $0.title,
                                      content: $0.turns.map(\.content).joined(separator: "\n"), updatedAt: $0.updatedAt)
                }
            } catch { failed += 1 }
        }
        return (entries.sorted { $0.updatedAt > $1.updatedAt }, failed)
    }
}

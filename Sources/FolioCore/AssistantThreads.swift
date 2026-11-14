import Foundation

public struct AssistantThread: Codable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var turns: [AssistantTurn]
    public init(title: String = "New chat", turns: [AssistantTurn] = []) {
        id = UUID(); self.title = AssistantThread.cleanTitle(title) ?? "New chat"; createdAt = Date(); updatedAt = Date(); self.turns = turns
    }
    public static func cleanTitle(_ raw: String) -> String? {
        let text = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return text.count > 60 ? String(text.prefix(58)) + "…" : text
    }
    public var hasDefaultTitle: Bool { title == "New chat" }
}

/// All conversation threads for one paper, saved locally beside the managed library.
public struct AssistantThreads: Codable, Equatable {
    public static let maxThreads = 40
    public var schemaVersion = 1
    public let paperID: UUID
    public let fingerprint: String
    public var threads: [AssistantThread]
    public var activeID: UUID?
    public init(paperID: UUID, fingerprint: String, threads: [AssistantThread] = []) {
        self.paperID = paperID; self.fingerprint = fingerprint; self.threads = threads; activeID = threads.first?.id
    }
    public var active: AssistantThread? { threads.first { $0.id == activeID } }

    @discardableResult public mutating func newThread() -> AssistantThread {
        // Reuse an existing empty chat instead of piling up blanks.
        if let empty = threads.first(where: { $0.turns.isEmpty }) { activeID = empty.id; return empty }
        if threads.count >= Self.maxThreads, let oldest = threads.min(by: { $0.updatedAt < $1.updatedAt }) { threads.removeAll { $0.id == oldest.id } }
        let thread = AssistantThread(); threads.insert(thread, at: 0); activeID = thread.id; return thread
    }
    public mutating func rename(_ id: UUID, to title: String) {
        guard let index = threads.firstIndex(where: { $0.id == id }), let clean = AssistantThread.cleanTitle(title) else { return }
        threads[index].title = clean
    }
    public mutating func delete(_ id: UUID) {
        threads.removeAll { $0.id == id }
        if activeID == id || !threads.contains(where: { $0.id == activeID }) { activeID = threads.first?.id }
    }
    /// Appends a finished exchange to the active thread, creating one when none exists.
    public mutating func append(question: String, answer: String, titleSource: String) {
        if active == nil { newThread() }
        guard let index = threads.firstIndex(where: { $0.id == activeID }) else { return }
        threads[index].turns += [AssistantTurn(role: .user, content: question), AssistantTurn(role: .assistant, content: answer)]
        if threads[index].turns.count > 96 { threads[index].turns.removeFirst(threads[index].turns.count - 96) }
        if threads[index].hasDefaultTitle, let title = AssistantThread.cleanTitle(titleSource) { threads[index].title = title }
        threads[index].updatedAt = Date()
    }
}

public final class AssistantThreadRepository {
    public let url: URL
    private let paperID: UUID
    private let fingerprint: String
    public init(root: URL, paperID: UUID, fingerprint: String) {
        self.paperID = paperID; self.fingerprint = fingerprint
        url = root.appendingPathComponent("Assistant", isDirectory: true).appendingPathComponent(paperID.uuidString + ".threads").appendingPathExtension("json")
    }
    /// Read-only. Legacy single-conversation turns become the first thread in memory until the next save.
    public func load(legacyTurns: [AssistantTurn]) throws -> AssistantThreads {
        guard FileManager.default.fileExists(atPath: url.path) else {
            var threads: [AssistantThread] = []
            if !legacyTurns.isEmpty {
                var thread = AssistantThread(title: AssistantThread.cleanTitle(legacyTurns.first?.content ?? "") ?? "Earlier conversation", turns: legacyTurns)
                thread.updatedAt = legacyTurns.last?.createdAt ?? Date(); threads = [thread]
            }
            return AssistantThreads(paperID: paperID, fingerprint: fingerprint, threads: threads)
        }
        guard let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber, size.intValue <= 8_000_000,
              let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(AssistantThreads.self, from: data) else { throw AssistantError.invalidData }
        try validate(saved)
        return saved
    }
    public func save(_ value: AssistantThreads) throws {
        try validate(value)
        let data = try JSONEncoder().encode(value)
        guard data.count <= 8_000_000 else { throw AssistantError.message("These conversations are too large to save.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private func validate(_ value: AssistantThreads) throws {
        guard value.schemaVersion == 1, value.paperID == paperID, value.fingerprint == fingerprint, value.threads.count <= AssistantThreads.maxThreads,
              Set(value.threads.map(\.id)).count == value.threads.count,
              value.activeID == nil || value.threads.contains(where: { $0.id == value.activeID }),
              value.threads.allSatisfy({ thread in
                  thread.title.count <= 80 && thread.turns.count <= 96 && thread.turns.count.isMultiple(of: 2) &&
                  thread.turns.enumerated().allSatisfy { index, turn in turn.role == (index.isMultiple(of: 2) ? .user : .assistant) && !turn.content.isEmpty && turn.content.count <= 64_000 }
              }) else { throw AssistantError.invalidData }
    }
}

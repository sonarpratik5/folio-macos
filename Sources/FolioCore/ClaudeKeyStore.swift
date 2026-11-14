import Foundation
import Security
import LocalAuthentication

/// The reader's Claude API key, stored only in this Mac's login Keychain (never in the library, defaults or logs).
/// `ANTHROPIC_API_KEY` in the launch environment still takes priority when set.
public enum ClaudeKeyStore {
    static let service = "dev.folio.mac.claude-api"
    static let account = "default"
    // Applies to secret reads and writes as well as presence checks. Login-Keychain ACLs
    // can change after an ad-hoc rebuild; unavailable access must fail inline, never prompt.
    static func nonInteractiveQuery() -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service, kSecAttrAccount as String: account,
                kSecUseAuthenticationContext as String: context,
                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
    }
    private static var query: [String: Any] { nonInteractiveQuery() }
    private static let session = CredentialSession()
    /// Secret access is reserved for an explicit Claude request. Reuse a successful unlock this session.
    public static func read() -> String? {
        session.read { readKeychain() }
    }
    private static func readKeychain() -> String? {
        var item: CFTypeRef?
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }
    /// Presence checks must never retrieve secret data or show an authentication dialog.
    public static var hasKey: Bool {
        if session.hasValue { return true }
        var q = query
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess
    }
    @discardableResult public static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete() }
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
            if added { session.replace(with: trimmed) }
            return added
        }
        if status == errSecSuccess { session.replace(with: trimmed) }
        return status == errSecSuccess
    }
    @discardableResult public static func delete() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        let deleted = status == errSecSuccess || status == errSecItemNotFound
        if deleted { session.replace(with: nil) }
        return deleted
    }
    /// `ANTHROPIC_API_KEY` from dotenv text (e.g. the web app's `.env`); handles `export`, quotes and comments.
    public static func key(fromDotEnv text: String) -> String? {
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard line.hasPrefix("ANTHROPIC_API_KEY"), let eq = line.firstIndex(of: "="),
                  line[..<eq].trimmingCharacters(in: .whitespaces) == "ANTHROPIC_API_KEY" else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'", let end = value.dropFirst().firstIndex(of: quote) {
                value = String(value[value.index(after: value.startIndex)..<end])
            } else if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
            value = value.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty, !value.hasPrefix("paste-") { return value }
        }
        return nil
    }
    /// Claude model: launch-environment override, then the Settings choice, then the default.
    public static let modelDefaultsKey = "folio.assistant.claudeModel"
    public static let models: [(id: String, name: String)] = [("claude-sonnet-5-5", "Claude Sonnet 5.5 · faster"), ("claude-opus-5-5", "Claude Opus 5.5 · most capable")]
    public static func model(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        environment["FOLIO_ASSISTANT_MODEL"] ?? UserDefaults.standard.string(forKey: modelDefaultsKey) ?? "claude-sonnet-5-5"
    }
}

/// Serializes unlocks and holds only a successfully retrieved credential in process memory.
/// Failed/cancelled unlocks can be retried by the next explicit request.
final class CredentialSession: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    var hasValue: Bool { lock.lock(); defer { lock.unlock() }; return value != nil }
    func read(_ loader: () -> String?) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let value { return value }
        value = loader()
        return value
    }
    func replace(with value: String?) {
        lock.lock(); defer { lock.unlock() }
        self.value = value
    }
}

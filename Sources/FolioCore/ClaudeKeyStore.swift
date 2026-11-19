import Foundation
import Security
import LocalAuthentication

/// The reader's Claude API key, stored only in this Mac's login Keychain (never in the library, defaults or logs).
/// Launch-environment credentials take priority over the local `.env`, then Keychain.
public enum ClaudeKeyStore {
    static let service = "dev.folio.mac.claude-api"
    private static let accountDefaultsKey = "folio.assistant.claudeKeyAccount"
    static var account: String { UserDefaults.standard.string(forKey: accountDefaultsKey) ?? "default" }
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
    // Legacy login-Keychain ACL authorization can ignore the item-query LA flags.
    // This Security.framework switch is process-local; it does not unlock a Keychain
    // or alter any item's ACL. Fail closed if the no-dialog policy cannot be set.
    private static let interactionDisabled = SecKeychainSetUserInteractionAllowed(false) == errSecSuccess
    @discardableResult public static func prepareNonInteractiveAccess() -> Bool { interactionDisabled }
    private static let session = CredentialSession()
    /// Secret access is reserved for an explicit Claude request. Reuse a successful unlock this session.
    public static func read() -> String? {
        session.read { readKeychain() }
    }
    private static func readKeychain() -> String? {
        guard prepareNonInteractiveAccess() else { return nil }
        var item: CFTypeRef?
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }
    /// Presence checks must never retrieve secret data or show an authentication dialog.
    public static var hasKey: Bool {
        if session.hasValue { return true }
        guard prepareNonInteractiveAccess() else { return false }
        var q = query
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess
    }
    @discardableResult public static func save(_ key: String) -> Bool {
        guard prepareNonInteractiveAccess() else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete() }
        // A new app build may not satisfy the old item's code-signature ACL. Save
        // a fresh app-owned item instead of trying to update an inaccessible item.
        let previous = query
        let nextAccount = UUID().uuidString
        var add = query
        add[kSecAttrAccount as String] = nextAccount
        add[kSecAttrLabel as String] = "Folio Claude API key"
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return false }
        UserDefaults.standard.set(nextAccount, forKey: accountDefaultsKey)
        session.replace(with: trimmed)
        // Best effort, still non-interactive. A denied old item stays in Keychain.
        _ = SecItemDelete(previous as CFDictionary)
        return true
    }
    @discardableResult public static func delete() -> Bool {
        guard prepareNonInteractiveAccess() else { return false }
        let status = SecItemDelete(query as CFDictionary)
        let deleted = status == errSecSuccess || status == errSecItemNotFound
        if deleted { session.replace(with: nil) }
        return deleted
    }
    public static func dotEnvKey(directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                                 bundleURL: URL = Bundle.main.bundleURL) -> String? {
        LocalDotEnv.value("ANTHROPIC_API_KEY", directory: directory, bundleURL: bundleURL)
    }
    public static func key(fromDotEnv text: String) -> String? {
        LocalDotEnv.value("ANTHROPIC_API_KEY", from: text)
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

import XCTest
import Security
import LocalAuthentication
@testable import FolioCore

final class CredentialSessionTests: XCTestCase {
    func testDotEnvDiscoveryFromWorkingDirectoryAndFinderBuildBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("native")
        let unrelated = root.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let bundle = project.appendingPathComponent(".build/Folio.app")
        XCTAssertNil(ClaudeKeyStore.dotEnvKey(directory: unrelated, bundleURL: bundle))
        try "export ANTHROPIC_API_KEY='synthetic-project-key' # local".write(to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeKeyStore.dotEnvKey(directory: unrelated, bundleURL: bundle), "synthetic-project-key")
        XCTAssertEqual(ClaudeKeyStore.dotEnvKey(directory: project, bundleURL: root), "synthetic-project-key")
        try "ANTHROPIC_API_KEY=synthetic-working-key".write(to: unrelated.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeKeyStore.dotEnvKey(directory: unrelated, bundleURL: bundle), "synthetic-working-key")
        XCTAssertNil(ClaudeKeyStore.dotEnvKey(directory: root, bundleURL: root.appendingPathComponent("Applications/Folio.app")))
    }

    func testInstalledBundleUsesConfiguredDotEnvPathWithoutWorkingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dotenv = root.appendingPathComponent("native.env")
        try "ANTHROPIC_API_KEY=synthetic-installed-key\nOPENREVIEW_TOKEN=synthetic-review-token".write(to: dotenv, atomically: true, encoding: .utf8)
        let movedBundle = root.appendingPathComponent("Applications/Folio.app")
        XCTAssertEqual(LocalDotEnv.value("ANTHROPIC_API_KEY", directory: root, bundleURL: movedBundle, configuredPath: dotenv.path), "synthetic-installed-key")
        XCTAssertEqual(LocalDotEnv.value("OPENREVIEW_TOKEN", directory: root, bundleURL: movedBundle, configuredPath: dotenv.path), "synthetic-review-token")
        XCTAssertNil(LocalDotEnv.value("ANTHROPIC_API_KEY", directory: root, bundleURL: movedBundle, configuredPath: root.appendingPathComponent("missing.env").path))
    }

    func testLegacyKeychainInteractionIsDisabledForThisProcess() {
        XCTAssertTrue(ClaudeKeyStore.prepareNonInteractiveAccess())
        var allowed = DarwinBoolean(true)
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
        XCTAssertFalse(allowed.boolValue)
    }

    func testEveryKeychainOperationUsesNonInteractivePolicy() throws {
        let query = ClaudeKeyStore.nonInteractiveQuery()
        let context = try XCTUnwrap(query[kSecUseAuthenticationContext as String] as? LAContext)
        XCTAssertTrue(context.interactionNotAllowed)
        XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String, kSecUseAuthenticationUIFail as String)
        XCTAssertNil(query[kSecReturnData as String])
    }

    func testSuccessfulUnlockIsReusedUntilReplacementOrRemoval() {
        let session = CredentialSession()
        var reads = 0
        func load() -> String? { reads += 1; return "synthetic-key" }
        XCTAssertEqual(session.read(load), "synthetic-key")
        XCTAssertEqual(session.read(load), "synthetic-key")
        XCTAssertEqual(reads, 1)
        session.replace(with: "replacement")
        XCTAssertEqual(session.read(load), "replacement")
        XCTAssertEqual(reads, 1)
        session.replace(with: nil)
        XCTAssertFalse(session.hasValue)
        XCTAssertEqual(session.read(load), "synthetic-key")
        XCTAssertEqual(reads, 2)
    }

    func testCancelledUnlockCanBeRetriedByExplicitRequest() {
        let session = CredentialSession()
        XCTAssertNil(session.read { nil })
        XCTAssertFalse(session.hasValue)
        XCTAssertEqual(session.read { "synthetic-key" }, "synthetic-key")
    }
}

import XCTest
import Security
import LocalAuthentication
@testable import FolioCore

final class CredentialSessionTests: XCTestCase {
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

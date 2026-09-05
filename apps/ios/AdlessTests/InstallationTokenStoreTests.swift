import Foundation
import XCTest
@testable import Adless

final class InstallationTokenStoreTests: XCTestCase {
    private let installationId = "11111111-1111-4111-8111-111111111111"
    private let firstDNS = String(repeating: "D", count: 43)
    private let firstStats = String(repeating: "S", count: 43)
    private let secondDNS = String(repeating: "E", count: 43)
    private let secondStats = String(repeating: "T", count: 43)

    func testCredentialsAndCurrentNonceCommitAsOneKeychainBlob() throws {
        let keychain = InMemoryInstallationKeychain()
        let random = DeterministicRandomSource()
        let store = InstallationTokenStore(keychain: keychain, randomData: random.data)

        let generatedInstallationId = try store.installationID()
        XCTAssertEqual(keychain.values.count, 1)
        let attempt = try store.authorizationAttempt(transactionId: "1000000000000001")
        XCTAssertTrue(attempt.isPendingRotation)
        XCTAssertNil(attempt.currentCredentials)
        XCTAssertEqual(keychain.values.count, 1)

        let credentials = InstallationCredentials(
            installationId: generatedInstallationId,
            dnsToken: firstDNS,
            statsToken: firstStats
        )
        try store.commit(
            credentials,
            transactionId: "1000000000000001",
            rotationNonce: attempt.rotationNonce
        )

        XCTAssertEqual(try store.credentials(), credentials)
        XCTAssertFalse(store.hasPendingAuthorization())
        XCTAssertEqual(keychain.values.count, 1, "installation, both tokens, and nonce must share one Keychain item")

        let restore = try store.authorizationAttempt(transactionId: "1000000000000001")
        XCTAssertEqual(restore.rotationNonce, attempt.rotationNonce)
        XCTAssertFalse(restore.isPendingRotation)
        XCTAssertNil(restore.currentCredentials)
    }

    func testFailedAtomicCommitKeepsPendingNonceForExactRetryAndHidesOldTokens() throws {
        let keychain = InMemoryInstallationKeychain()
        let random = DeterministicRandomSource()
        let store = InstallationTokenStore(keychain: keychain, randomData: random.data)
        let installationId = try store.installationID()
        let firstAttempt = try store.authorizationAttempt(transactionId: "1000000000000001")
        try store.commit(
            InstallationCredentials(installationId: installationId, dnsToken: firstDNS, statsToken: firstStats),
            transactionId: "1000000000000001",
            rotationNonce: firstAttempt.rotationNonce
        )

        let rotation = try store.authorizationAttempt(transactionId: "1000000000000002")
        XCTAssertNil(try store.credentials(), "old tokens must not be reused while a server rotation may have committed")
        keychain.failNextWrite = true
        XCTAssertThrowsError(try store.commit(
            InstallationCredentials(installationId: installationId, dnsToken: secondDNS, statsToken: secondStats),
            transactionId: "1000000000000002",
            rotationNonce: rotation.rotationNonce
        ))

        let retry = try store.authorizationAttempt(transactionId: "1000000000000002")
        XCTAssertEqual(retry.rotationNonce, rotation.rotationNonce)
        XCTAssertTrue(retry.isPendingRotation)
        XCTAssertNil(try store.credentials())

        let replacement = InstallationCredentials(
            installationId: installationId,
            dnsToken: secondDNS,
            statsToken: secondStats
        )
        try store.commit(
            replacement,
            transactionId: "1000000000000002",
            rotationNonce: retry.rotationNonce
        )
        XCTAssertEqual(try store.credentials(), replacement)
    }

    func testNewVerifiedTransactionSupersedesAStalePendingAttempt() throws {
        let keychain = InMemoryInstallationKeychain()
        let random = DeterministicRandomSource()
        let store = InstallationTokenStore(keychain: keychain, randomData: random.data)
        let installationId = try store.installationID()
        let original = try store.authorizationAttempt(transactionId: "1000000000000001")
        try store.commit(
            InstallationCredentials(installationId: installationId, dnsToken: firstDNS, statsToken: firstStats),
            transactionId: "1000000000000001",
            rotationNonce: original.rotationNonce
        )

        let stale = try store.authorizationAttempt(transactionId: "1000000000000002")
        let current = try store.authorizationAttempt(transactionId: "1000000000000003")
        XCTAssertNotEqual(current.rotationNonce, stale.rotationNonce)
        XCTAssertTrue(current.isPendingRotation)
        XCTAssertNil(current.currentCredentials)
        XCTAssertNil(try store.credentials(), "the previously configured tokens stay hidden during the new rotation")

        let retry = try store.authorizationAttempt(transactionId: "1000000000000003")
        XCTAssertEqual(retry.rotationNonce, current.rotationNonce)

        let replacement = InstallationCredentials(
            installationId: installationId,
            dnsToken: secondDNS,
            statsToken: secondStats
        )
        try store.commit(
            replacement,
            transactionId: "1000000000000003",
            rotationNonce: retry.rotationNonce
        )
        XCTAssertEqual(try store.credentials(), replacement)
    }

    func testLegacySeparateItemsMigrateBeforeSendingCredentialProof() throws {
        let keychain = InMemoryInstallationKeychain()
        keychain.seed(
            Data(installationId.utf8),
            service: "com.orbeworks.adless.credentials",
            account: "installation-id"
        )
        keychain.seed(
            Data(firstDNS.utf8),
            service: "com.orbeworks.adless.credentials",
            account: "dns-token"
        )
        keychain.seed(
            Data(firstStats.utf8),
            service: "com.orbeworks.adless.credentials",
            account: "stats-token"
        )
        let store = InstallationTokenStore(
            keychain: keychain,
            randomData: DeterministicRandomSource().data
        )

        let attempt = try store.authorizationAttempt(transactionId: "1000000000000001")
        XCTAssertEqual(
            attempt.currentCredentials,
            InstallationCredentials(installationId: installationId, dnsToken: firstDNS, statsToken: firstStats)
        )
        XCTAssertTrue(attempt.isPendingRotation)
        XCTAssertEqual(keychain.values.count, 1, "successful migration must leave only the atomic state item")
        XCTAssertNil(try store.credentials(), "legacy tokens are hidden while their reconciliation is pending")
    }
}

private final class InMemoryInstallationKeychain: InstallationKeychainDataStore, @unchecked Sendable {
    struct Key: Hashable {
        let service: String
        let account: String
    }

    enum Failure: Error {
        case write
    }

    private(set) var values: [Key: Data] = [:]
    var failNextWrite = false

    func seed(_ data: Data, service: String, account: String) {
        values[Key(service: service, account: account)] = data
    }

    func read(service: String, account: String) throws -> Data? {
        values[Key(service: service, account: account)]
    }

    func write(_ data: Data, service: String, account: String) throws {
        if failNextWrite {
            failNextWrite = false
            throw Failure.write
        }
        values[Key(service: service, account: account)] = data
    }

    func remove(service: String, account: String) throws {
        values.removeValue(forKey: Key(service: service, account: account))
    }
}

private final class DeterministicRandomSource: @unchecked Sendable {
    private var nextByte: UInt8 = 1

    func data(count: Int) throws -> Data {
        defer { nextByte &+= 1 }
        return Data(repeating: nextByte, count: count)
    }
}

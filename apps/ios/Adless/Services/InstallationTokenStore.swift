import Foundation
import Security

struct InstallationCredentials: Equatable, Sendable {
    let installationId: String
    let dnsToken: String
    let statsToken: String
}

struct InstallationAuthorizationAttempt: Equatable, Sendable {
    let rotationNonce: String
    let currentCredentials: InstallationCredentials?
    let isPendingRotation: Bool
}

enum InstallationTokenStoreError: LocalizedError {
    case randomGenerationFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    case authorizationRequired
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed:
            return "Could not create secure authorization data"
        case .keychainReadFailed:
            return "Could not read Adless credentials"
        case .keychainWriteFailed:
            return "Could not store Adless credentials"
        case .keychainDeleteFailed:
            return "Could not remove old Adless credentials"
        case .authorizationRequired:
            return "Subscription authorization is required"
        case .invalidCredentials:
            return "Adless received invalid credentials"
        }
    }
}

protocol InstallationKeychainDataStore: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func remove(service: String, account: String) throws
}

struct SystemInstallationKeychainDataStore: InstallationKeychainDataStore {
    func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw InstallationTokenStoreError.keychainReadFailed(status)
        }
        return result as? Data
    }

    func write(_ data: Data, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw InstallationTokenStoreError.keychainWriteFailed(updateStatus)
        }

        var addQuery = query
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw InstallationTokenStoreError.keychainWriteFailed(retryStatus)
            }
        } else if addStatus != errSecSuccess {
            throw InstallationTokenStoreError.keychainWriteFailed(addStatus)
        }
    }

    func remove(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw InstallationTokenStoreError.keychainDeleteFailed(status)
        }
    }
}

struct InstallationTokenStore: Sendable {
    static let shared = InstallationTokenStore()

    private struct StoredState: Codable, Equatable {
        let schemaVersion: Int
        var installationId: String
        var dnsToken: String?
        var statsToken: String?
        var currentTransactionId: String?
        var currentRotationNonce: String?
        var pendingTransactionId: String?
        var pendingRotationNonce: String?
        var pendingUsesCredentialProof: Bool
    }

    private let service = "com.orbeworks.adless.credentials"
    private let stateAccount = "installation-state-v2"
    private let legacyService = "com.orbeworks.adless.installation-token"
    private let legacyServiceAccount = BuildEnvironment.bundleIdentifier
    private let legacyInstallationAccount = "installation-id"
    private let legacyDNSAccount = "dns-token"
    private let legacyStatsAccount = "stats-token"
    private let tokenByteCount = 32
    private let keychain: any InstallationKeychainDataStore
    private let randomData: @Sendable (Int) throws -> Data

    init(
        keychain: any InstallationKeychainDataStore = SystemInstallationKeychainDataStore(),
        randomData: @escaping @Sendable (Int) throws -> Data = InstallationTokenStore.secureRandomData
    ) {
        self.keychain = keychain
        self.randomData = randomData
    }

    func installationID() throws -> String {
        if let state = try loadOrMigrateState() {
            return state.installationId
        }

        let state = StoredState(
            schemaVersion: 2,
            installationId: UUID().uuidString,
            dnsToken: nil,
            statsToken: nil,
            currentTransactionId: nil,
            currentRotationNonce: nil,
            pendingTransactionId: nil,
            pendingRotationNonce: nil,
            pendingUsesCredentialProof: false
        )
        try persist(state)
        return state.installationId
    }

    func credentials() throws -> InstallationCredentials? {
        guard let state = try loadOrMigrateState(),
              state.pendingRotationNonce == nil,
              let credentials = credentials(from: state) else {
            return nil
        }
        return credentials
    }

    func hasAuthorizedCredentials() -> Bool {
        do {
            return try credentials() != nil
        } catch {
            return false
        }
    }

    func dnsToken() throws -> String {
        guard let credentials = try credentials() else { throw InstallationTokenStoreError.authorizationRequired }
        return credentials.dnsToken
    }

    func statsToken() throws -> String {
        guard let credentials = try credentials() else { throw InstallationTokenStoreError.authorizationRequired }
        return credentials.statsToken
    }

    /// Returns the nonce for this StoreKit transaction. A new nonce is saved
    /// before the authorization request leaves the device. Retries for the
    /// same transaction therefore remain idempotent after a lost response or
    /// a failed Keychain commit.
    func authorizationAttempt(transactionId: String) throws -> InstallationAuthorizationAttempt {
        guard Self.isValidTransactionID(transactionId) else {
            throw InstallationTokenStoreError.invalidCredentials
        }
        var state = try stateCreatingIfNeeded()

        if state.pendingTransactionId == transactionId,
           let pendingNonce = state.pendingRotationNonce {
            return InstallationAuthorizationAttempt(
                rotationNonce: pendingNonce,
                currentCredentials: state.pendingUsesCredentialProof ? credentials(from: state) : nil,
                isPendingRotation: true
            )
        }
        if state.currentTransactionId == transactionId,
           let currentNonce = state.currentRotationNonce,
           credentials(from: state) != nil {
            return InstallationAuthorizationAttempt(
                rotationNonce: currentNonce,
                currentCredentials: nil,
                isPendingRotation: false
            )
        }

        let replacesDifferentPendingTransaction = state.pendingRotationNonce != nil
        let nonce = try Self.base64URLToken(from: randomData(tokenByteCount))
        let needsCredentialProof = !replacesDifferentPendingTransaction
            && state.currentRotationNonce == nil
            && credentials(from: state) != nil
        state.pendingTransactionId = transactionId
        state.pendingRotationNonce = nonce
        state.pendingUsesCredentialProof = needsCredentialProof
        try persist(state)
        return InstallationAuthorizationAttempt(
            rotationNonce: nonce,
            currentCredentials: needsCredentialProof ? credentials(from: state) : nil,
            isPendingRotation: true
        )
    }

    /// Atomically replaces both bearer tokens and promotes the pending nonce
    /// to the current transaction. If this one Keychain write fails, the old
    /// state and pending nonce remain available for an exact retry.
    func commit(
        _ credentials: InstallationCredentials,
        transactionId: String,
        rotationNonce: String
    ) throws {
        guard Self.valid(credentials),
              Self.isValidTransactionID(transactionId),
              Self.isValid(rotationNonce),
              var state = try loadOrMigrateState(),
              state.installationId == credentials.installationId else {
            throw InstallationTokenStoreError.invalidCredentials
        }

        let matchesPending = state.pendingTransactionId == transactionId
            && state.pendingRotationNonce == rotationNonce
        let matchesCurrent = state.pendingRotationNonce == nil
            && state.currentTransactionId == transactionId
            && state.currentRotationNonce == rotationNonce
        guard matchesPending || matchesCurrent else {
            throw InstallationTokenStoreError.invalidCredentials
        }

        state.dnsToken = credentials.dnsToken
        state.statsToken = credentials.statsToken
        state.currentTransactionId = transactionId
        state.currentRotationNonce = rotationNonce
        state.pendingTransactionId = nil
        state.pendingRotationNonce = nil
        state.pendingUsesCredentialProof = false
        try persist(state)
        removeLegacyItemsBestEffort()
    }

    func hasPendingAuthorization() -> Bool {
        do {
            return try loadOrMigrateState()?.pendingRotationNonce != nil
        } catch {
            return true
        }
    }

    /// The old MVP stored one bearer token under this service. It is read only
    /// to let the first successful server authorization replace it; its value
    /// is never sent or logged.
    func hasLegacyToken() throws -> Bool {
        guard let data = try keychain.read(service: legacyService, account: legacyServiceAccount) else { return false }
        return data.count == tokenByteCount
    }

    /// Kept as a compatibility name for callers outside the current target.
    func token() throws -> String {
        try dnsToken()
    }

    nonisolated static func isValid(_ token: String) -> Bool {
        token.count == 43
            && token.unicodeScalars.allSatisfy { scalar in
                (48...57).contains(scalar.value)
                    || (65...90).contains(scalar.value)
                    || (97...122).contains(scalar.value)
                    || scalar.value == 45
                    || scalar.value == 95
            }
    }

    nonisolated private static func valid(_ credentials: InstallationCredentials) -> Bool {
        isValidInstallationID(credentials.installationId)
            && isValid(credentials.dnsToken)
            && isValid(credentials.statsToken)
            && credentials.dnsToken != credentials.statsToken
    }

    nonisolated private static func isValidInstallationID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    nonisolated private static func isValidTransactionID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.allSatisfy(\.isNumber)
    }

    nonisolated private static func base64URLToken(from data: Data) throws -> String {
        guard data.count == 32 else { throw InstallationTokenStoreError.invalidCredentials }
        let token = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard isValid(token) else { throw InstallationTokenStoreError.invalidCredentials }
        return token
    }

    nonisolated private static func secureRandomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw InstallationTokenStoreError.randomGenerationFailed(status)
        }
        return data
    }

    private func stateCreatingIfNeeded() throws -> StoredState {
        if let state = try loadOrMigrateState() { return state }
        _ = try installationID()
        guard let state = try loadOrMigrateState() else {
            throw InstallationTokenStoreError.invalidCredentials
        }
        return state
    }

    private func loadOrMigrateState() throws -> StoredState? {
        if let data = try keychain.read(service: service, account: stateAccount) {
            guard let state = try? JSONDecoder().decode(StoredState.self, from: data),
                  Self.valid(state) else {
                throw InstallationTokenStoreError.invalidCredentials
            }
            return state
        }

        guard let installationData = try keychain.read(service: service, account: legacyInstallationAccount),
              let installationId = String(data: installationData, encoding: .utf8),
              Self.isValidInstallationID(installationId) else {
            return nil
        }

        let dnsToken = try legacyToken(account: legacyDNSAccount)
        let statsToken = try legacyToken(account: legacyStatsAccount)
        let legacyCredentials = dnsToken.flatMap { dns in
            statsToken.map { stats in
                InstallationCredentials(installationId: installationId, dnsToken: dns, statsToken: stats)
            }
        }
        let coherentCredentials = legacyCredentials.flatMap { Self.valid($0) ? $0 : nil }
        let state = StoredState(
            schemaVersion: 2,
            installationId: installationId,
            dnsToken: coherentCredentials?.dnsToken,
            statsToken: coherentCredentials?.statsToken,
            currentTransactionId: nil,
            currentRotationNonce: nil,
            pendingTransactionId: nil,
            pendingRotationNonce: nil,
            pendingUsesCredentialProof: false
        )
        try persist(state)
        removeLegacyItemsBestEffort()
        return state
    }

    nonisolated private static func valid(_ state: StoredState) -> Bool {
        guard state.schemaVersion == 2,
              isValidInstallationID(state.installationId) else { return false }

        let credentialsAreAbsent = state.dnsToken == nil && state.statsToken == nil
        let credentialsAreValid = state.dnsToken.flatMap { dns in
            state.statsToken.map { stats in
                isValid(dns) && isValid(stats) && dns != stats
            }
        } ?? false
        guard credentialsAreAbsent || credentialsAreValid else { return false }

        let currentMetadataIsAbsent = state.currentTransactionId == nil && state.currentRotationNonce == nil
        let currentMetadataIsValid = state.currentTransactionId.map(isValidTransactionID) == true
            && state.currentRotationNonce.map(isValid) == true
            && credentialsAreValid
        guard currentMetadataIsAbsent || currentMetadataIsValid else { return false }

        let pendingIsAbsent = state.pendingTransactionId == nil
            && state.pendingRotationNonce == nil
            && !state.pendingUsesCredentialProof
        let pendingIsValid = state.pendingTransactionId.map(isValidTransactionID) == true
            && state.pendingRotationNonce.map(isValid) == true
            && (!state.pendingUsesCredentialProof || credentialsAreValid)
        return pendingIsAbsent || pendingIsValid
    }

    private func credentials(from state: StoredState) -> InstallationCredentials? {
        guard let dnsToken = state.dnsToken,
              let statsToken = state.statsToken else { return nil }
        let credentials = InstallationCredentials(
            installationId: state.installationId,
            dnsToken: dnsToken,
            statsToken: statsToken
        )
        return Self.valid(credentials) ? credentials : nil
    }

    private func legacyToken(account: String) throws -> String? {
        guard let data = try keychain.read(service: service, account: account),
              let value = String(data: data, encoding: .utf8),
              Self.isValid(value) else {
            return nil
        }
        return value
    }

    private func persist(_ state: StoredState) throws {
        guard Self.valid(state) else { throw InstallationTokenStoreError.invalidCredentials }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try keychain.write(try encoder.encode(state), service: service, account: stateAccount)
    }

    private func removeLegacyItemsBestEffort() {
        for (legacyItemService, legacyItemAccount) in [
            (service, legacyInstallationAccount),
            (service, legacyDNSAccount),
            (service, legacyStatsAccount),
            (legacyService, legacyServiceAccount)
        ] {
            try? keychain.remove(service: legacyItemService, account: legacyItemAccount)
        }
    }
}

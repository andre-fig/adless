import Foundation
import Security

struct InstallationCredentials: Equatable, Sendable {
    let installationId: String
    let dnsToken: String
    let statsToken: String
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
            return "Could not create the installation identifier"
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

struct InstallationTokenStore: Sendable {
    static let shared = InstallationTokenStore()

    private let service = "com.orbeworks.adless.credentials"
    private let legacyService = "com.orbeworks.adless.installation-token"
    private let account = BuildEnvironment.bundleIdentifier
    private let installationAccount = "installation-id"
    private let dnsAccount = "dns-token"
    private let statsAccount = "stats-token"
    private let tokenByteCount = 32

    func installationID() throws -> String {
        if let existing = try readString(account: installationAccount), Self.isValidInstallationID(existing) {
            return existing
        }

        let value = UUID().uuidString
        try write(Data(value.utf8), account: installationAccount)
        return value
    }

    func credentials() throws -> InstallationCredentials? {
        guard let installationId = try readString(account: installationAccount),
              Self.isValidInstallationID(installationId),
              let dnsToken = try readString(account: dnsAccount),
              let statsToken = try readString(account: statsAccount),
              Self.isValid(dnsToken),
              Self.isValid(statsToken) else {
            return nil
        }
        return InstallationCredentials(installationId: installationId, dnsToken: dnsToken, statsToken: statsToken)
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

    func save(_ credentials: InstallationCredentials) throws {
        guard Self.isValidInstallationID(credentials.installationId),
              Self.isValid(credentials.dnsToken),
              Self.isValid(credentials.statsToken) else {
            throw InstallationTokenStoreError.invalidCredentials
        }

        try write(Data(credentials.installationId.utf8), account: installationAccount)
        try write(Data(credentials.dnsToken.utf8), account: dnsAccount)
        try write(Data(credentials.statsToken.utf8), account: statsAccount)
        try removeLegacyToken()
    }

    /// The old MVP stored one bearer token under this service. It is read only
    /// to let the first successful server authorization replace it; its value
    /// is never sent or logged.
    func hasLegacyToken() throws -> Bool {
        guard let data = try readData(service: legacyService, account: account) else { return false }
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

    private static func isValidInstallationID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    private func readString(account: String) throws -> String? {
        guard let data = try readData(service: service, account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func readData(service: String, account: String) throws -> Data? {
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

    private func write(_ data: Data, account: String) throws {
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

    private func removeLegacyToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw InstallationTokenStoreError.keychainDeleteFailed(status)
        }
    }
}

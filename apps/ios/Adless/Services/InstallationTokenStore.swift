import Foundation
import Security

enum InstallationTokenStoreError: LocalizedError {
    case randomGenerationFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed:
            return "Could not create the installation token"
        case .keychainReadFailed:
            return "Could not read the installation token"
        case .keychainWriteFailed:
            return "Could not store the installation token"
        }
    }
}

struct InstallationTokenStore: Sendable {
    static let shared = InstallationTokenStore()

    private let service = "com.orbeworks.adless.installation-token"
    private let account = BuildEnvironment.bundleIdentifier
    private let tokenByteCount = 32

    func token() throws -> String {
        if let existing = try read() {
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: tokenByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw InstallationTokenStoreError.randomGenerationFailed(errSecInternalError)
        }
        let data = Data(bytes)
        let value = Self.base64URL(data)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            if let existing = try read() { return existing }
        }
        guard status == errSecSuccess else {
            throw InstallationTokenStoreError.keychainWriteFailed(status)
        }
        return value
    }

    private func read() throws -> String? {
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
        guard let data = result as? Data, data.count == tokenByteCount else { return nil }
        return Self.base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

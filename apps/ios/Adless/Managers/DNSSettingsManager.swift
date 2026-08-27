import Foundation
@preconcurrency import NetworkExtension

enum DNSSettingsState: String, Equatable {
    case notConfigured
    case disabled
    case enabled
    case invalid
}

enum DNSSettingsManagerError: LocalizedError {
    case invalidEndpoint
    case configurationNotOwned

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The DNS protection endpoint is invalid"
        case .configurationNotOwned:
            return "The DNS protection configuration is invalid"
        }
    }
}

/// Serializes the system-owned DNS Settings preference lifecycle.
///
/// iOS exposes `isEnabled` as read-only. Saving creates or updates the
/// configuration; the user must approve it in Settings before it becomes
/// active. Removing the configuration disables it and is the supported
/// deactivation operation.
@available(iOS 14.0, *)
actor DNSSettingsManager {
    private let systemManager = NEDNSSettingsManager.shared()

    func install() async throws -> DNSSettingsState {
        try await load()

        let token = try InstallationTokenStore.shared.token()
        let endpoint = try DNSCloudConfiguration.endpointURL(for: token)
        let settings = NEDNSOverHTTPSSettings(servers: [])
        settings.serverURL = endpoint
        settings.matchDomains = [""]
        settings.matchDomainsNoSearch = true
        if #available(iOS 26.0, *) {
            settings.allowFailover = false
        }

        systemManager.localizedDescription = BuildEnvironment.displayName
        systemManager.dnsSettings = settings
        systemManager.onDemandRules = nil
        try await save()

        // The object is stale after save; reload before reporting state.
        try await load()
        return try ownedState()
    }

    func remove() async throws {
        try await load()
        guard systemManager.dnsSettings != nil else { return }
        guard isOwnedConfiguration else {
            throw DNSSettingsManagerError.configurationNotOwned
        }
        try await removeFromPreferences()
    }

    func currentState() async -> DNSSettingsState {
        do {
            try await load()
            return try ownedState()
        } catch {
            AdlessSentry.capture(error, operation: "dns.settings.load")
            return .invalid
        }
    }

    private var isOwnedConfiguration: Bool {
        guard let settings = systemManager.dnsSettings as? NEDNSOverHTTPSSettings,
              let serverURL = settings.serverURL else {
            return false
        }
        return DNSCloudConfiguration.isAdlessEndpoint(serverURL)
    }

    private func ownedState() throws -> DNSSettingsState {
        guard systemManager.dnsSettings != nil else { return .notConfigured }
        guard isOwnedConfiguration else { throw DNSSettingsManagerError.configurationNotOwned }
        return systemManager.isEnabled ? .enabled : .disabled
    }

    private func load() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            systemManager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        AdlessSentry.event("dns.settings.load")
    }

    private func save() async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                systemManager.saveToPreferences { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            AdlessSentry.event("dns.settings.save")
        } catch {
            AdlessSentry.capture(error, operation: "dns.settings.save")
            throw error
        }
    }

    private func removeFromPreferences() async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                systemManager.removeFromPreferences { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            AdlessSentry.event("dns.settings.remove")
        } catch {
            AdlessSentry.capture(error, operation: "dns.settings.remove")
            throw error
        }
    }
}

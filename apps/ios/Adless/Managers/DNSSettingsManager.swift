import Foundation
@preconcurrency import NetworkExtension

enum DNSSettingsState: String, Equatable {
    case notConfigured
    case disabled
    case enabled
    case staleEnabled
    case invalid

    var isSystemEnabled: Bool {
        self == .enabled || self == .staleEnabled
    }
}

enum DNSSettingsManagerError: LocalizedError {
    case invalidEndpoint
    case configurationNotOwned
    case removalNotConfirmed

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The DNS protection endpoint is invalid"
        case .configurationNotOwned:
            return "The DNS protection configuration is invalid"
        case .removalNotConfirmed:
            return "Adless could not confirm that DNS protection was removed. Disable it manually in Settings."
        }
    }
}

/// The small portion of `NEDNSSettingsManager` used by Adless. Keeping this
/// boundary explicit lets the preference lifecycle be tested without asking a
/// Simulator to install a real system DNS configuration.
nonisolated protocol DNSSettingsPreferencesManaging: AnyObject {
    var localizedDescription: String? { get set }
    var dnsSettings: NEDNSSettings? { get set }
    var onDemandRules: [NEOnDemandRule]? { get set }
    var isEnabled: Bool { get }

    func loadFromPreferences(completionHandler: @escaping @Sendable (Error?) -> Void)
    func saveToPreferences(completionHandler: @escaping @Sendable (Error?) -> Void)
    func removeFromPreferences(completionHandler: @escaping @Sendable (Error?) -> Void)
}

nonisolated extension NEDNSSettingsManager: DNSSettingsPreferencesManaging {}

/// Serializes the system-owned DNS Settings preference lifecycle.
///
/// iOS exposes `isEnabled` as read-only. Saving creates or updates the
/// configuration; the user must approve it in Settings before it becomes
/// active. Removing the configuration disables it and is the supported
/// deactivation operation.
@available(iOS 14.0, *)
actor DNSSettingsManager {
    typealias EndpointProvider = @MainActor @Sendable () throws -> URL

    private let systemManager: any DNSSettingsPreferencesManaging
    private let endpointProvider: EndpointProvider

    init(
        systemManager: any DNSSettingsPreferencesManaging = NEDNSSettingsManager.shared(),
        endpointProvider: @escaping EndpointProvider = {
            let token = try InstallationTokenStore.shared.dnsToken()
            return try DNSCloudConfiguration.endpointURL(for: token)
        }
    ) {
        self.systemManager = systemManager
        self.endpointProvider = endpointProvider
    }

    func install() async throws -> DNSSettingsState {
        do {
            try await load()

            let endpoint = try await endpointProvider()
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
            return try await ownedState()
        } catch {
            // Assigning `dnsSettings` mutates this process's in-memory object
            // before `saveToPreferences` finishes. If the save fails, reload
            // the persisted configuration so an older enabled profile remains
            // the source of truth instead of the unsaved replacement.
            do {
                try await load()
            } catch {
                AdlessSentry.capture(error, operation: "dns.settings.reload_after_install_failure")
            }
            throw error
        }
    }

    func remove() async throws {
        try await load()
        guard systemManager.dnsSettings != nil else { return }
        guard isOwnedConfiguration else {
            throw DNSSettingsManagerError.configurationNotOwned
        }
        try await removeFromPreferences()
        try await load()
        guard systemManager.dnsSettings == nil else {
            throw DNSSettingsManagerError.removalNotConfirmed
        }
    }

    func currentState() async -> DNSSettingsState {
        do {
            try await load()
            return try await ownedState()
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

    private func ownedState() async throws -> DNSSettingsState {
        guard systemManager.dnsSettings != nil else { return .notConfigured }
        guard isOwnedConfiguration else { throw DNSSettingsManagerError.configurationNotOwned }
        guard systemManager.isEnabled else { return .disabled }

        // A successful server-side rotation can precede the local preference
        // save. In that window the old Adless profile is still enabled, but
        // its superseded token is intentionally pass-through. Treat it as a
        // real enabled system configuration without claiming that blocking is
        // active. If credentials are pending or unreadable, the expected URL
        // is likewise unconfirmed and therefore stale.
        guard let settings = systemManager.dnsSettings as? NEDNSOverHTTPSSettings,
              let configuredEndpoint = settings.serverURL,
              let currentEndpoint = try? await endpointProvider(),
              configuredEndpoint == currentEndpoint,
              settings.matchDomains == [""],
              settings.matchDomainsNoSearch else {
            return .staleEnabled
        }
        return .enabled
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

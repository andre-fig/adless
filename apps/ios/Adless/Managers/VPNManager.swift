import Foundation
@preconcurrency import NetworkExtension

/// Serializes Network Extension preference mutations. Network Extension
/// preferences are asynchronous and must be reloaded after saving before a
/// session is started; keeping the whole sequence in an actor prevents two
/// taps or lifecycle callbacks from interleaving it.
actor VPNManager {
    private let providerBundleIdentifier = BuildEnvironment.packetTunnelBundleIdentifier
    private let appGroup = BuildEnvironment.appGroupIdentifier
    private let displayName = BuildEnvironment.displayName

    func start() async throws {
        do {
            AdlessSentry.event("vpn.load")
            let manager = try await loadOrCreateManager()
            manager.isEnabled = true
            AdlessSentry.event("vpn.save")
            try await save(manager)

            AdlessSentry.event("vpn.reload")
            let reloaded = try await loadConfiguredManager()
            guard let session = reloaded.connection as? NETunnelProviderSession else {
                throw VPNManagerError.invalidSession
            }

            try session.startVPNTunnel(options: nil)
            AdlessSentry.event("vpn.start", status: reloaded.connection.status)
        } catch {
            AdlessSentry.capture(error, operation: "vpn.start")
            throw error
        }
    }

    func stop() async throws {
        do {
            AdlessSentry.event("vpn.load")
            let manager = try await loadConfiguredManager()
            let status = manager.connection.status
            AdlessSentry.event("vpn.stop", status: status)
            if status != .disconnected && status != .invalid {
                manager.connection.stopVPNTunnel()
            }
        } catch {
            AdlessSentry.capture(error, operation: "vpn.stop")
            throw error
        }
    }

    func currentStatus() async -> NEVPNStatus {
        do {
            let manager = try await loadConfiguredManager()
            let status = manager.connection.status
            AdlessSentry.event("vpn.status_change", status: status)
            return status
        } catch {
            AdlessSentry.capture(error, operation: "vpn.load")
            return .invalid
        }
    }

    func reloadProviderBlocklist() async {
        do {
            let manager = try await loadConfiguredManager()
            guard let session = manager.connection as? NETunnelProviderSession else { return }
            guard manager.connection.status == .connected || manager.connection.status == .reasserting else {
                return
            }

            AdlessSentry.event("vpn.reload")
            try await sendReloadMessage(to: session)
        } catch {
            // A provider that is in the middle of a lifecycle transition will
            // load the latest atomically written file on its next start. Do
            // not tear down a healthy tunnel just to refresh its in-memory set.
            AdlessSentry.capture(error, operation: "vpn.reload")
        }
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        let managers = try await loadAll()
        if let existing = managers.first(where: matches) {
            configure(existing)
            return existing
        }

        let manager = NETunnelProviderManager()
        configure(manager)
        return manager
    }

    private func loadConfiguredManager() async throws -> NETunnelProviderManager {
        let managers = try await loadAll()
        guard let manager = managers.first(where: matches) else {
            throw VPNManagerError.configurationNotFound
        }
        return manager
    }

    private func matches(_ manager: NETunnelProviderManager) -> Bool {
        guard let configuration = manager.protocolConfiguration as? NETunnelProviderProtocol else {
            return false
        }
        return configuration.providerBundleIdentifier == providerBundleIdentifier
    }

    private func configure(_ manager: NETunnelProviderManager) {
        let configuration: NETunnelProviderProtocol
        if let current = manager.protocolConfiguration as? NETunnelProviderProtocol {
            configuration = current
        } else {
            configuration = NETunnelProviderProtocol()
        }
        // NEVPNProtocol requires a server address even for a local Packet
        // Tunnel. This is only the provider configuration's required marker;
        // no connection is opened to localhost and no remote VPN is used.
        configuration.serverAddress = "127.0.0.1"
        configuration.providerBundleIdentifier = providerBundleIdentifier
        configuration.providerConfiguration = ["appGroup": appGroup]
        manager.protocolConfiguration = configuration
        manager.localizedDescription = displayName
        manager.isEnabled = true
    }

    private func loadAll() async throws -> [NETunnelProviderManager] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[NETunnelProviderManager], Error>) in
            NETunnelProviderManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers ?? [])
                }
            }
        }
    }

    private func save(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func sendReloadMessage(to session: NETunnelProviderSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try session.sendProviderMessage(Data("reloadBlocklist".utf8)) { _ in
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private enum VPNManagerError: LocalizedError {
    case configurationNotFound
    case invalidSession

    var errorDescription: String? {
        switch self {
        case .configurationNotFound: return "Adless VPN configuration was not found"
        case .invalidSession: return "Adless VPN session is unavailable"
        }
    }
}

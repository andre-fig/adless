import Foundation
@preconcurrency import NetworkExtension

final class VPNManager {
    private let providerBundleIdentifier = BuildEnvironment.dnsProxyBundleIdentifier
    private let appGroup = BuildEnvironment.appGroupIdentifier
    private let simulatorFlagKey = "sim.vpn.enabled"

    func start() async throws {
        if isSimulator {
            UserDefaults.standard.set(true, forKey: simulatorFlagKey)
            return
        }
        let manager = try await prepareManager()
        manager.isEnabled = true
        try await save(manager)
    }

    func stop() async throws {
        if isSimulator {
            UserDefaults.standard.set(false, forKey: simulatorFlagKey)
            return
        }
        let manager = try await loadManager()
        manager.isEnabled = false
        try await save(manager)
    }

    func currentStatus() async -> NEVPNStatus {
        if isSimulator {
            return UserDefaults.standard.bool(forKey: simulatorFlagKey) ? .connected : .disconnected
        }
        let manager = try? await loadManager()
        return (manager?.isEnabled ?? false) ? .connected : .disconnected
    }

    func reloadProviderBlocklist() async {
        if isSimulator { return }
        // Reapply preferences to prompt the system to reload the extension with updated blocklists.
        try? await stop()
        try? await start()
    }

    private func loadManager() async throws -> NEDNSProxyManager {
        let manager = NEDNSProxyManager.shared()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NEDNSProxyManager, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: manager)
                }
            }
        }
    }

    private func prepareManager() async throws -> NEDNSProxyManager {
        let manager = try await loadManager()
        if manager.providerProtocol == nil {
            let proto = NEDNSProxyProviderProtocol()
            proto.providerBundleIdentifier = providerBundleIdentifier
            proto.providerConfiguration = ["appGroup": appGroup]
            proto.serverAddress = "127.0.0.1"
            manager.localizedDescription = "Adless DNS"
            manager.providerProtocol = proto
        }
        return manager
    }

    private func save(_ manager: NEDNSProxyManager) async throws {
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

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

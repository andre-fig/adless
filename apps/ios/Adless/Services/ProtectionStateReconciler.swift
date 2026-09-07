import Foundation

enum RemoteBlockingState: Equatable, Sendable {
    case unknown
    case enabled
    case paused
}

struct ProtectionReconciliationRequirements: Equatable, Sendable {
    let hasAccess: Bool
    let hasCredentials: Bool
    let authorizationRequired: Bool

    var canQueryWorker: Bool {
        hasAccess && hasCredentials && !authorizationRequired
    }
}

struct ProtectionReconciliationSnapshot: Equatable, Sendable {
    let requirements: ProtectionReconciliationRequirements
    let dnsState: DNSSettingsState?
    let remoteBlockingState: RemoteBlockingState
    let isChecking: Bool

    var isProtectionActive: Bool {
        requirements.canQueryWorker
            && dnsState == .enabled
            && remoteBlockingState == .enabled
    }
}

/// Reconciles the two independent switches that make protection effective:
/// the system DNS setting and the per-installation preference in the Worker.
/// Every run gets a generation; late results from older runs are discarded.
@MainActor
final class ProtectionStateReconciler {
    typealias DNSStateLoader = @Sendable () async -> DNSSettingsState
    typealias RemoteStateLoader = @Sendable () async throws -> Bool
    typealias SnapshotHandler = (ProtectionReconciliationSnapshot) -> Void

    private var generation: UInt64 = 0

    func invalidate(
        requirements: ProtectionReconciliationRequirements,
        onSnapshot: SnapshotHandler
    ) {
        generation &+= 1
        onSnapshot(ProtectionReconciliationSnapshot(
            requirements: requirements,
            dnsState: nil,
            remoteBlockingState: .unknown,
            isChecking: requirements.canQueryWorker
        ))
    }

    @discardableResult
    func reconcile(
        requirements: ProtectionReconciliationRequirements,
        loadDNSState: @escaping DNSStateLoader,
        loadRemoteState: @escaping RemoteStateLoader,
        onSnapshot: SnapshotHandler
    ) async -> DNSSettingsState? {
        generation &+= 1
        let currentGeneration = generation

        onSnapshot(ProtectionReconciliationSnapshot(
            requirements: requirements,
            dnsState: nil,
            remoteBlockingState: .unknown,
            isChecking: requirements.canQueryWorker
        ))

        let remoteTask: Task<RemoteBlockingState, Never>? = requirements.canQueryWorker
            ? Task {
                do {
                    return try await loadRemoteState() ? .enabled : .paused
                } catch {
                    return .unknown
                }
            }
            : nil

        let initialDNSState = await loadDNSState()
        guard currentGeneration == generation else {
            remoteTask?.cancel()
            return nil
        }

        onSnapshot(ProtectionReconciliationSnapshot(
            requirements: requirements,
            dnsState: initialDNSState,
            remoteBlockingState: .unknown,
            isChecking: remoteTask != nil
        ))

        guard let remoteTask else { return initialDNSState }
        let remoteBlockingState = await remoteTask.value
        guard currentGeneration == generation else { return nil }

        // The DNS setting may have changed while the network request was in
        // flight. Re-read it before publishing a remotely confirmed state.
        let finalDNSState = await loadDNSState()
        guard currentGeneration == generation else { return nil }

        onSnapshot(ProtectionReconciliationSnapshot(
            requirements: requirements,
            dnsState: finalDNSState,
            remoteBlockingState: remoteBlockingState,
            isChecking: false
        ))
        return finalDNSState
    }
}

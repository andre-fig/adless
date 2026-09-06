import XCTest
@testable import Adless

@MainActor
final class ProtectionStateReconcilerTests: XCTestCase {
    private let validRequirements = ProtectionReconciliationRequirements(
        hasAccess: true,
        hasCredentials: true,
        authorizationRequired: false
    )

    func testDNSActiveAndWorkerEnabledIsActive() async {
        let snapshot = await finalSnapshot(dnsState: .enabled) { true }

        XCTAssertEqual(snapshot.remoteBlockingState, .enabled)
        XCTAssertTrue(snapshot.isProtectionActive)
    }

    func testDNSActiveAndWorkerPausedIsPaused() async {
        let snapshot = await finalSnapshot(dnsState: .enabled) { false }

        XCTAssertEqual(snapshot.remoteBlockingState, .paused)
        XCTAssertFalse(snapshot.isProtectionActive)
    }

    func testDNSActiveAndWorkerUnavailableIsUnknown() async {
        let snapshot = await finalSnapshot(dnsState: .enabled) {
            throw RemoteFailure.unavailable
        }

        XCTAssertEqual(snapshot.remoteBlockingState, .unknown)
        XCTAssertFalse(snapshot.isChecking)
        XCTAssertFalse(snapshot.isProtectionActive)
    }

    func testDNSDisabledAndWorkerEnabledIsInactiveImmediately() async {
        let reconciler = ProtectionStateReconciler()
        let gate = RemoteResponseGate()
        var snapshots: [ProtectionReconciliationSnapshot] = []
        let task = Task { @MainActor in
            await reconciler.reconcile(
                requirements: validRequirements,
                loadDNSState: { .disabled },
                loadRemoteState: { try await gate.load() },
                onSnapshot: { snapshots.append($0) }
            )
        }

        await gate.waitUntilRequested()
        await waitUntil { snapshots.contains(where: { $0.dnsState == .disabled }) }
        let immediate = try! XCTUnwrap(snapshots.last)
        XCTAssertEqual(immediate.remoteBlockingState, .unknown)
        XCTAssertFalse(immediate.isProtectionActive)

        await gate.succeed(true)
        _ = await task.value
        XCTAssertEqual(snapshots.last?.remoteBlockingState, .enabled)
        XCTAssertFalse(snapshots.last?.isProtectionActive == true)
    }

    func testManualSettingsActivationIgnoresOldTrueCache() async {
        let reconciler = ProtectionStateReconciler()
        var snapshots: [ProtectionReconciliationSnapshot] = []

        _ = await reconciler.reconcile(
            requirements: validRequirements,
            loadDNSState: { .enabled },
            loadRemoteState: { true },
            onSnapshot: { snapshots.append($0) }
        )
        XCTAssertTrue(snapshots.last?.isProtectionActive == true)

        _ = await reconciler.reconcile(
            requirements: validRequirements,
            loadDNSState: { .enabled },
            loadRemoteState: { false },
            onSnapshot: { snapshots.append($0) }
        )

        XCTAssertEqual(snapshots.last?.remoteBlockingState, .paused)
        XCTAssertFalse(snapshots.last?.isProtectionActive == true)
    }

    func testManualSettingsActivationIgnoresOldFalseCache() async {
        let reconciler = ProtectionStateReconciler()
        var snapshots: [ProtectionReconciliationSnapshot] = []

        _ = await reconciler.reconcile(
            requirements: validRequirements,
            loadDNSState: { .enabled },
            loadRemoteState: { false },
            onSnapshot: { snapshots.append($0) }
        )
        XCTAssertFalse(snapshots.last?.isProtectionActive == true)

        _ = await reconciler.reconcile(
            requirements: validRequirements,
            loadDNSState: { .enabled },
            loadRemoteState: { true },
            onSnapshot: { snapshots.append($0) }
        )

        XCTAssertEqual(snapshots.last?.remoteBlockingState, .enabled)
        XCTAssertTrue(snapshots.last?.isProtectionActive == true)
    }

    func testForegroundReconciliationFetchesWorkerAgain() async {
        let reconciler = ProtectionStateReconciler()
        let remote = MutableRemoteState(true)
        var snapshots: [ProtectionReconciliationSnapshot] = []

        _ = await reconciler.reconcile(
            requirements: validRequirements,
            loadDNSState: { .enabled },
            loadRemoteState: { await remote.load() },
            onSnapshot: { snapshots.append($0) }
        )
        XCTAssertTrue(snapshots.last?.isProtectionActive == true)

        await remote.set(false)
        _ = await reconciler.reconcile(
            requirements: validRequirements,
            loadDNSState: { .enabled },
            loadRemoteState: { await remote.load() },
            onSnapshot: { snapshots.append($0) }
        )
        XCTAssertEqual(snapshots.last?.remoteBlockingState, .paused)
        XCTAssertFalse(snapshots.last?.isProtectionActive == true)
    }

    func testDNSChangeDuringRemoteRequestIsReadBeforePublishing() async {
        let reconciler = ProtectionStateReconciler()
        let dns = MutableDNSState(.enabled)
        let gate = RemoteResponseGate()
        var snapshots: [ProtectionReconciliationSnapshot] = []
        let task = Task { @MainActor in
            await reconciler.reconcile(
                requirements: validRequirements,
                loadDNSState: { await dns.load() },
                loadRemoteState: { try await gate.load() },
                onSnapshot: { snapshots.append($0) }
            )
        }

        await gate.waitUntilRequested()
        await waitUntil { snapshots.contains(where: { $0.dnsState == .enabled }) }
        await dns.set(.disabled)
        await gate.succeed(true)
        _ = await task.value

        XCTAssertEqual(snapshots.last?.dnsState, .disabled)
        XCTAssertEqual(snapshots.last?.remoteBlockingState, .enabled)
        XCTAssertFalse(snapshots.last?.isProtectionActive == true)
    }

    func testOlderRemoteResponseCannotOverwriteNewReconciliation() async {
        let reconciler = ProtectionStateReconciler()
        let oldGate = RemoteResponseGate()
        let newGate = RemoteResponseGate()
        var snapshots: [ProtectionReconciliationSnapshot] = []

        let oldTask = Task { @MainActor in
            await reconciler.reconcile(
                requirements: validRequirements,
                loadDNSState: { .enabled },
                loadRemoteState: { try await oldGate.load() },
                onSnapshot: { snapshots.append($0) }
            )
        }
        await oldGate.waitUntilRequested()

        let newTask = Task { @MainActor in
            await reconciler.reconcile(
                requirements: validRequirements,
                loadDNSState: { .enabled },
                loadRemoteState: { try await newGate.load() },
                onSnapshot: { snapshots.append($0) }
            )
        }
        await newGate.waitUntilRequested()
        await newGate.succeed(false)
        _ = await newTask.value
        XCTAssertEqual(snapshots.last?.remoteBlockingState, .paused)

        await oldGate.succeed(true)
        let discardedResult = await oldTask.value
        XCTAssertNil(discardedResult)
        XCTAssertEqual(snapshots.last?.remoteBlockingState, .paused)
        XCTAssertFalse(snapshots.last?.isProtectionActive == true)
    }

    private func finalSnapshot(
        dnsState: DNSSettingsState,
        remote: @escaping ProtectionStateReconciler.RemoteStateLoader
    ) async -> ProtectionReconciliationSnapshot {
        let reconciler = ProtectionStateReconciler()
        var snapshots: [ProtectionReconciliationSnapshot] = []
        _ = await reconciler.reconcile(
            requirements: validRequirements,
            loadDNSState: { dnsState },
            loadRemoteState: remote,
            onSnapshot: { snapshots.append($0) }
        )
        return try! XCTUnwrap(snapshots.last)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}

private enum RemoteFailure: Error {
    case unavailable
}

private actor MutableDNSState {
    private var state: DNSSettingsState

    init(_ state: DNSSettingsState) {
        self.state = state
    }

    func load() -> DNSSettingsState {
        state
    }

    func set(_ state: DNSSettingsState) {
        self.state = state
    }
}

private actor MutableRemoteState {
    private var enabled: Bool

    init(_ enabled: Bool) {
        self.enabled = enabled
    }

    func load() -> Bool {
        enabled
    }

    func set(_ enabled: Bool) {
        self.enabled = enabled
    }
}

private actor RemoteResponseGate {
    private var continuation: CheckedContinuation<Bool, Error>?
    private var requested = false

    func load() async throws -> Bool {
        requested = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequested() async {
        while !requested {
            await Task.yield()
        }
    }

    func succeed(_ enabled: Bool) {
        continuation?.resume(returning: enabled)
        continuation = nil
    }
}

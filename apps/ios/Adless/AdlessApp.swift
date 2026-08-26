import SwiftUI
import Combine
import NetworkExtension
import Sentry

@main
struct AdlessApp: App {
    @StateObject private var viewModel = AppViewModel()

    init() {
        AdlessSentry.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isOn: Bool = false
    @Published var statusText: String = String(localized: "Off")
    @Published private(set) var isPreparing = true
    @Published private(set) var hasSubscription = false
    @Published var isSubscriptionPresented = false
    @Published private(set) var blockedTodayCount = 0
    @Published private(set) var allTimeBlockCount = 0

    private var blocklistManager: BlocklistManager?
    private let blockingStatsStore = BlockingStatsStore()
    private let vpnManager = VPNManager()
    let subscriptionManager = SubscriptionManager()
    private var vpnStatusObserver: NSObjectProtocol?

    init() {
        subscriptionManager.onEntitlementChanged = { [weak self] hasAccess in
            guard let self else { return }
            self.hasSubscription = hasAccess
            guard !hasAccess else { return }
            Task { @MainActor [weak self] in
                await self?.disableIfSubscriptionExpired()
            }
        }
        subscriptionManager.onPurchaseCompleted = { [weak self] in
            guard let self, self.subscriptionManager.hasActiveEntitlement else { return }
            self.hasSubscription = true
            self.isSubscriptionPresented = false
            Task { @MainActor [weak self] in
                await self?.activateBlocking()
            }
        }
        vpnStatusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshStatus()
            }
        }
        beginPreparation()

#if DEBUG && os(iOS) && targetEnvironment(simulator)
        if !ProcessInfo.processInfo.arguments.contains("-useStoreKitProducts") {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.isSubscriptionPresented = true
            }
        }
#endif
    }

    deinit {
        if let vpnStatusObserver {
            NotificationCenter.default.removeObserver(vpnStatusObserver)
        }
    }

    var blockedCount: Int {
        blocklistManager?.cachedCount ?? 0
    }

    @MainActor
    func toggle() async {
        guard !isPreparing else { return }
        guard hasSubscription else {
            isSubscriptionPresented = true
            return
        }

        if isOn {
            let transaction = AdlessSentry.startTransaction(name: "protection.deactivate", operation: "networkextension")
            defer { transaction?.finish() }
            do {
                try await vpnManager.stop()
                await refreshStatus()
            } catch {
                AdlessSentry.capture(error, operation: "protection.deactivate")
                statusText = String(localized: "Could not change blocking status")
            }
            return
        }

        await activateBlocking()
    }

    @MainActor
    func activateBlocking() async {
        guard !isPreparing, let blocklistManager else { return }
        guard hasSubscription else {
            isSubscriptionPresented = true
            return
        }

        // Reflect the user's action immediately. The Network Extension can
        // take a moment to save and start its configuration, so waiting for it
        // before changing the published state makes the button appear stuck.
        isOn = true
        statusText = String(localized: "Connecting")
        await Task.yield()

        let transaction = AdlessSentry.startTransaction(name: "protection.activate", operation: "networkextension")
        defer { transaction?.finish() }

        do {
            _ = try blocklistManager.ensureActiveBlocklist()
            try await vpnManager.start()
            await refreshStatus()
        } catch {
            AdlessSentry.capture(error, operation: "protection.activate")
            isOn = false
            statusText = String(localized: "Could not change blocking status")
        }
    }

    @MainActor
    func refreshStatus() async {
        let state = await vpnManager.currentStatus()
        isOn = hasSubscription && isProtectionActive(state)
        if !hasSubscription {
            statusText = String(localized: "Premium access required")
            return
        }
        switch state {
        case .invalid: statusText = String(localized: "Invalid")
        case .disconnected: statusText = String(localized: "Off")
        case .connecting: statusText = String(localized: "Connecting")
        case .connected: statusText = String(localized: "On")
        case .reasserting: statusText = String(localized: "Reconnecting")
        case .disconnecting: statusText = String(localized: "Disconnecting")
        @unknown default: statusText = String(localized: "Unknown")
        }
    }

    @MainActor
    func refreshBlockingStats() {
        let snapshot = blockingStatsStore.read()
        blockedTodayCount = snapshot.todayCount
        allTimeBlockCount = snapshot.allTimeCount
    }

    @MainActor
    func applicationDidBecomeActive() async {
        guard !isPreparing, let blocklistManager else { return }
        refreshBlockingStats()
        await subscriptionManager.loadAndRefresh()
        hasSubscription = subscriptionManager.hasActiveEntitlement
        await disableIfSubscriptionExpired()
        await refreshStatus()

        guard hasSubscription else { return }
        let result = await blocklistManager.refreshIfNeeded()
        if case .updated = result, isOn {
            await vpnManager.reloadProviderBlocklist()
        }
    }

    private func beginPreparation() {
        let preparationStartedAt = Date()
        let minimumPreparationDuration: TimeInterval = 0.35

        DispatchQueue.global(qos: .userInitiated).async {
            let manager = BlocklistManager()
            let elapsed = Date().timeIntervalSince(preparationStartedAt)
            let remaining = max(0, minimumPreparationDuration - elapsed)

            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.finishPreparation(with: manager)
                }
            }
        }
    }

    @MainActor
    private func finishPreparation(with manager: BlocklistManager) async {
        blocklistManager = manager
        hasSubscription = subscriptionManager.hasActiveEntitlement

        let state = await vpnManager.currentStatus()
        let wasAlreadyActive = isProtectionActive(state)
        isOn = hasSubscription && wasAlreadyActive
        statusText = isOn ? String(localized: "On") : String(localized: "Off")

        isPreparing = false
        await applicationDidBecomeActive()
    }

    @MainActor
    private func disableIfSubscriptionExpired() async {
        guard !hasSubscription else { return }
        let state = await vpnManager.currentStatus()
        guard isProtectionActive(state) else { return }
        try? await vpnManager.stop()
        isOn = false
        statusText = String(localized: "Premium access required")
    }

    private func isProtectionActive(_ state: NEVPNStatus) -> Bool {
        state == .connected || state == .connecting || state == .reasserting
    }
}

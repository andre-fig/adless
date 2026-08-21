import SwiftUI
import Combine
import NetworkExtension

@main
struct AdlessApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}

final class AppViewModel: ObservableObject {
    @Published var isOn: Bool = false
    @Published var statusText: String = "Off"
    @Published private(set) var isPreparing = true
    @Published private(set) var hasSubscription = false
    @Published var isSubscriptionPresented = false
    @Published private(set) var blockedTodayCount = 0
    @Published private(set) var allTimeBlockCount = 0

    private var blocklistManager: BlocklistManager?
    private let blockingStatsStore = BlockingStatsStore()
    private let vpnManager = VPNManager()
    let subscriptionManager = SubscriptionManager()

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
            do {
                try await vpnManager.stop()
                await refreshStatus()
            } catch {
                statusText = "Could not change blocking status"
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
        statusText = "Connecting"
        await Task.yield()

        do {
            _ = try blocklistManager.ensureActiveBlocklist()
            try await vpnManager.start()
            await refreshStatus()
        } catch {
            isOn = false
            statusText = "Could not change blocking status"
        }
    }

    @MainActor
    func refreshStatus() async {
        let state = await vpnManager.currentStatus()
        isOn = hasSubscription && (state == .connected || state == .connecting)
        if !hasSubscription {
            statusText = "Premium access required"
            return
        }
        switch state {
        case .invalid: statusText = "Invalid"
        case .disconnected: statusText = "Off"
        case .connecting: statusText = "Connecting"
        case .connected: statusText = "On"
        case .reasserting: statusText = "Reconnecting"
        case .disconnecting: statusText = "Disconnecting"
        @unknown default: statusText = "Unknown"
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
        guard let blocklistManager else { return }
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
                guard let self else { return }
                self.blocklistManager = manager
                self.isPreparing = false
                Task { @MainActor [weak self] in
                    await self?.applicationDidBecomeActive()
                }
            }
        }
    }

    @MainActor
    private func disableIfSubscriptionExpired() async {
        guard !hasSubscription else { return }
        let state = await vpnManager.currentStatus()
        guard state == .connected || state == .connecting else { return }
        try? await vpnManager.stop()
        isOn = false
        statusText = "Premium access required"
    }
}

import SwiftUI
import Combine
import Foundation
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
    @Published var isOn = false
    @Published var statusText: String = String(localized: "Off")
    @Published private(set) var isPreparing = true
    @Published private(set) var hasSubscription = false
    @Published var isSubscriptionPresented = false
    @Published var isSystemApprovalAlertPresented = false
    @Published private(set) var blockedTodayCount = 0
    @Published private(set) var allTimeBlockCount = 0

    let subscriptionManager = SubscriptionManager()

    private let dnsSettingsManager = DNSSettingsManager()
    private let blockingStatsStore = BlockingStatsStore()
    private let statsAPIClient = DNSStatsAPIClient()
    private var dnsSettingsObserver: NSObjectProtocol?

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
                await self?.activateProtection()
            }
        }

        dnsSettingsObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NEDNSSettingsConfigurationDidChangeNotification"),
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
        if let dnsSettingsObserver {
            NotificationCenter.default.removeObserver(dnsSettingsObserver)
        }
    }

    @MainActor
    func toggle() async {
        guard !isPreparing else { return }
        guard hasSubscription else {
            isSubscriptionPresented = true
            return
        }

        if isOn {
            let transaction = AdlessSentry.startTransaction(name: "protection.deactivate", operation: "dns-settings")
            defer { transaction?.finish() }
            do {
                try await dnsSettingsManager.remove()
                await refreshStatus()
            } catch {
                AdlessSentry.capture(error, operation: "dns.settings.remove")
                statusText = String(localized: "Could not change blocking status")
            }
            return
        }

        await activateProtection()
    }

    @MainActor
    func activateProtection() async {
        guard !isPreparing, hasSubscription else {
            isSubscriptionPresented = true
            return
        }

        statusText = String(localized: "Connecting")
        let transaction = AdlessSentry.startTransaction(name: "protection.activate", operation: "dns-settings")
        defer { transaction?.finish() }

        do {
            let state = try await dnsSettingsManager.install()
            await refreshStatus()
            await refreshCloudStats()
            if state == .disabled {
                isSystemApprovalAlertPresented = true
            }
        } catch {
            AdlessSentry.capture(error, operation: "dns.settings.save")
            isOn = false
            statusText = String(localized: "Could not change blocking status")
        }
    }

    @MainActor
    func refreshStatus() async {
        let state = await dnsSettingsManager.currentState()
        isOn = hasSubscription && state == .enabled
        AdlessSentry.event("dns.settings.status_change", state: state.rawValue)

        if !hasSubscription {
            statusText = String(localized: "Premium access required")
            return
        }

        switch state {
        case .notConfigured, .disabled:
            statusText = String(localized: "Off")
        case .enabled:
            statusText = String(localized: "On")
        case .invalid:
            statusText = String(localized: "Invalid")
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
        await subscriptionManager.loadAndRefresh()
        hasSubscription = subscriptionManager.hasActiveEntitlement
        await disableIfSubscriptionExpired()
        await refreshStatus()
        refreshBlockingStats()
        await refreshCloudStats()
    }

    private func refreshCloudStats() async {
        guard hasSubscription else { return }
        do {
            let total = try await statsAPIClient.fetchBlockedTotal()
            let snapshot = blockingStatsStore.updateRemoteTotal(total)
            blockedTodayCount = snapshot.todayCount
            allTimeBlockCount = snapshot.allTimeCount
        } catch {
            // The cached total remains visible. Statistics are best effort and
            // must never disable or delay DNS protection.
            AdlessSentry.capture(error, operation: "stats.fetch")
            refreshBlockingStats()
        }
    }

    private func beginPreparation() {
        let preparationStartedAt = Date()
        let minimumPreparationDuration: TimeInterval = 0.35
        let elapsed = Date().timeIntervalSince(preparationStartedAt)
        let remaining = max(0, minimumPreparationDuration - elapsed)

        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hasSubscription = self.subscriptionManager.hasActiveEntitlement
                self.isPreparing = false
                await self.applicationDidBecomeActive()
            }
        }
    }

    @MainActor
    private func disableIfSubscriptionExpired() async {
        guard !hasSubscription else { return }
        let state = await dnsSettingsManager.currentState()
        guard state == .enabled || state == .disabled else { return }
        try? await dnsSettingsManager.remove()
        isOn = false
        statusText = String(localized: "Premium access required")
    }
}

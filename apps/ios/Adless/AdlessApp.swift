import SwiftUI
import Combine
import Foundation
import UIKit
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
    @Published var isManualDisableAlertPresented = false
    @Published private(set) var blockedTodayCount = 0
    @Published private(set) var allTimeBlockCount = 0

    let subscriptionManager = SubscriptionManager()

    private let dnsSettingsManager = DNSSettingsManager()
    private let blockingStatsStore = BlockingStatsStore()
    private let statsAPIClient = DNSStatsAPIClient()
    private let authorizationAPIClient = DNSAuthorizationAPIClient()
    private var dnsSettingsObserver: NSObjectProtocol?
    private var isAuthorizing = false
    private var authorizationRequired = false

    init() {
        subscriptionManager.onEntitlementChanged = { [weak self] hasAccess in
            guard let self else { return }
            self.hasSubscription = hasAccess
            self.authorizationRequired = true
            if hasAccess {
                Task { @MainActor [weak self] in
                    await self?.ensureAuthorizationIfNeeded()
                }
                return
            }
            Task { @MainActor [weak self] in
                await self?.disableIfSubscriptionExpired()
            }
        }
        subscriptionManager.onPurchaseCompleted = { [weak self] transactionJWS in
            guard let self, self.subscriptionManager.hasActiveEntitlement else { return }
            self.hasSubscription = true
            self.authorizationRequired = true
            Task { @MainActor [weak self] in
                await self?.authorizeAndActivate(transactionJWS: transactionJWS)
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
                await refreshStatus()
                isManualDisableAlertPresented = true
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

        if authorizationRequired || !InstallationTokenStore.shared.hasAuthorizedCredentials() {
            guard let transactionJWS = await subscriptionManager.currentEntitlementJWS() else {
                subscriptionManager.showAuthorizationFailure()
                return
            }
            await authorizeAndActivate(transactionJWS: transactionJWS)
            return
        }

        // Saving a DNS configuration does not enable it. Once iOS has saved a
        // disabled configuration, trying to save it again does not help the
        // user and can make the activation button appear to do nothing. Keep
        // the user in the explicit system-approval flow until the setting is
        // enabled in Settings.
        if await dnsSettingsManager.currentState() == .disabled {
            isSystemApprovalAlertPresented = true
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

    /// Opens the system DNS configuration screen after the app has saved the
    /// profile. iOS has no public URL for General > VPN & Network > DNS, so
    /// this is a best-effort use of the undocumented Settings URL route. The
    /// user must still enable Adless in Settings.
    @MainActor
    func openSystemDNSSettings() {
        let settingsURLs = [
            "prefs:root=General&path=ManagedConfigurationList/DNS",
            "prefs:root=General&path=VPN/DNS",
            "App-Prefs:root=General"
        ].compactMap(URL.init(string:))

        openNextSettingsURL(settingsURLs, at: 0)
    }

    @MainActor
    private func openNextSettingsURL(_ urls: [URL], at index: Int) {
        guard urls.indices.contains(index) else { return }

        UIApplication.shared.open(urls[index], options: [:]) { [weak self] didOpen in
            guard !didOpen else { return }
            Task { @MainActor [weak self] in
                self?.openNextSettingsURL(urls, at: index + 1)
            }
        }
    }

    @MainActor
    func refreshStatus() async {
        let state = await dnsSettingsManager.currentState()
        isOn = state == .enabled
        if isOn {
            // Returning from Settings triggers this refresh. Do not require
            // an extra confirmation tap once iOS reports the DNS setting as
            // enabled.
            isSystemApprovalAlertPresented = false
        }
        AdlessSentry.event("dns.settings.status_change", state: state.rawValue)

        if !hasSubscription {
            statusText = state == .enabled
                ? String(localized: "Protection is still active; disable Adless in Settings.")
                : String(localized: "Premium access required")
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
        await ensureAuthorizationIfNeeded()
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

    private func ensureAuthorizationIfNeeded() async {
        guard hasSubscription, authorizationRequired || !InstallationTokenStore.shared.hasAuthorizedCredentials() else { return }
        guard let transactionJWS = await subscriptionManager.currentEntitlementJWS() else {
            subscriptionManager.showAuthorizationFailure()
            return
        }
        await authorizeAndActivate(transactionJWS: transactionJWS)
    }

    private func authorizeAndActivate(transactionJWS: String) async {
        guard hasSubscription, !isAuthorizing else { return }
        isAuthorizing = true
        defer { isAuthorizing = false }
        statusText = String(localized: "Authorizing")
        do {
            let installationId = try InstallationTokenStore.shared.installationID()
            let credentials = try await authorizationAPIClient.authorize(
                transactionJWS: transactionJWS,
                installationId: installationId
            )
            try InstallationTokenStore.shared.save(credentials)
            authorizationRequired = false
            isSubscriptionPresented = false
            await activateProtection()
        } catch {
            AdlessSentry.capture(error, operation: "subscription.authorization")
            subscriptionManager.showAuthorizationFailure()
            await refreshStatus()
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
        do {
            try await dnsSettingsManager.remove()
            isOn = false
            statusText = String(localized: "Premium access required")
        } catch {
            AdlessSentry.capture(error, operation: "dns.settings.remove")
            await refreshStatus()
            isManualDisableAlertPresented = true
        }
    }
}

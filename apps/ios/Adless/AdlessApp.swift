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
    static func authorizationIsRequired(
        hasAccess: Bool,
        hasCredentials: Bool,
        source: SubscriptionAuthorizationSource? = nil
    ) -> Bool {
        guard hasAccess else { return false }
        guard hasCredentials else { return true }
        return source != nil
    }

    static func protectionIsConfirmed(
        hasAccess: Bool,
        hasCredentials: Bool,
        authorizationRequired: Bool,
        dnsState: DNSSettingsState
    ) -> Bool {
        hasAccess && hasCredentials && !authorizationRequired && dnsState == .enabled
    }

    static func shouldActivateAfterAuthorization(
        explicitlyRequested: Bool,
        previousDNSState: DNSSettingsState
    ) -> Bool {
        explicitlyRequested || previousDNSState.isSystemEnabled
    }

    @Published var isOn = false
    @Published private(set) var isProtectionActive = false
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
    private var needsStartupAuthorizationReconciliation = true

    init() {
        subscriptionManager.onEntitlementChanged = { [weak self] hasAccess in
            guard let self else { return }
            self.hasSubscription = hasAccess
            self.authorizationRequired = Self.authorizationIsRequired(
                hasAccess: hasAccess,
                hasCredentials: InstallationTokenStore.shared.hasAuthorizedCredentials()
            )
            if self.authorizationRequired || !hasAccess {
                self.isProtectionActive = false
            }
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
        subscriptionManager.onPurchaseCompleted = { [weak self] authorization, source in
            guard let self, self.subscriptionManager.hasActiveEntitlement else { return }
            self.hasSubscription = true
            let hasCredentials = InstallationTokenStore.shared.hasAuthorizedCredentials()
            self.authorizationRequired = Self.authorizationIsRequired(
                hasAccess: true,
                hasCredentials: hasCredentials,
                source: source
            )
            if self.authorizationRequired {
                self.isProtectionActive = false
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.authorizationRequired {
                    await self.authorizeAndActivate(
                        authorization,
                        shouldActivateAfterAuthorization: true
                    )
                } else {
                    await self.activateProtection()
                }
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

        if isProtectionActive {
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
            guard let authorization = await subscriptionManager.currentEntitlementAuthorization() else {
                subscriptionManager.showAuthorizationFailure()
                return
            }
            await authorizeAndActivate(
                authorization,
                shouldActivateAfterAuthorization: true
            )
            return
        }

        // Always reinstall the profile when activating. This also migrates a
        // previously saved, disabled profile to the current authorized DoH
        // URL and credential. The real state is read back after save; do not
        // optimistically change the UI before iOS confirms it.
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
            let state = await refreshStatus()
            if state == .disabled {
                isSystemApprovalAlertPresented = true
            }
        }
    }

    /// Opens the root of the Settings app after the app has saved the profile.
    /// iOS has no public URL for the DNS screen, so this is a best-effort use
    /// of the undocumented root Settings URL. The user must still enable
    /// Adless in Settings.
    @MainActor
    func openSystemDNSSettings() {
        let settingsURLs = [
            "App-Prefs:",
            "prefs:"
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
    @discardableResult
    func refreshStatus() async -> DNSSettingsState {
        let state = await dnsSettingsManager.currentState()
        isOn = state.isSystemEnabled
        isProtectionActive = Self.protectionIsConfirmed(
            hasAccess: hasSubscription,
            hasCredentials: InstallationTokenStore.shared.hasAuthorizedCredentials(),
            authorizationRequired: authorizationRequired,
            dnsState: state
        )
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
            return state
        }

        switch state {
        case .notConfigured, .disabled:
            statusText = String(localized: "Off")
        case .enabled:
            statusText = String(localized: "On")
        case .staleEnabled:
            statusText = String(localized: "Reconnect to update DNS protection")
        case .invalid:
            statusText = String(localized: "Invalid")
        }
        return state
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
        if needsStartupAuthorizationReconciliation, hasSubscription {
            authorizationRequired = true
            isProtectionActive = false
        }
        needsStartupAuthorizationReconciliation = false
        await ensureAuthorizationIfNeeded()
        await disableIfSubscriptionExpired()
        await refreshStatus()
        refreshBlockingStats()
        await refreshCloudStats()
    }

    private func refreshCloudStats() async {
        guard isProtectionActive else { return }
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
        guard let authorization = await subscriptionManager.currentEntitlementAuthorization() else {
            subscriptionManager.showAuthorizationFailure()
            return
        }
        let previousDNSState = await dnsSettingsManager.currentState()
        await authorizeAndActivate(
            authorization,
            shouldActivateAfterAuthorization: Self.shouldActivateAfterAuthorization(
                explicitlyRequested: false,
                previousDNSState: previousDNSState
            )
        )
    }

    private func authorizeAndActivate(
        _ authorization: SubscriptionAuthorization,
        shouldActivateAfterAuthorization: Bool
    ) async {
        guard hasSubscription, !isAuthorizing else { return }
        isAuthorizing = true
        defer { isAuthorizing = false }
        authorizationRequired = true
        isProtectionActive = false
        statusText = String(localized: "Authorizing")
        var receivedCredentials = false
        var attempt: InstallationAuthorizationAttempt?
        do {
            let appTransactionJWS = await subscriptionManager.currentAppTransactionJWS()
            let installationId = try InstallationTokenStore.shared.installationID()
            let preparedAttempt = try InstallationTokenStore.shared.authorizationAttempt(
                transactionId: authorization.transactionId
            )
            attempt = preparedAttempt
            let credentials = try await authorizationAPIClient.authorize(
                transactionJWS: authorization.transactionJWS,
                appTransactionJWS: appTransactionJWS,
                installationId: installationId,
                rotationNonce: preparedAttempt.rotationNonce,
                currentCredentials: preparedAttempt.currentCredentials
            )
            receivedCredentials = true
            try InstallationTokenStore.shared.commit(
                credentials,
                transactionId: authorization.transactionId,
                rotationNonce: preparedAttempt.rotationNonce
            )
            authorizationRequired = false
            isSubscriptionPresented = false
            if shouldActivateAfterAuthorization {
                await activateProtection()
            } else {
                await refreshStatus()
            }
        } catch {
            authorizationRequired = true
            isProtectionActive = false
            AdlessSentry.capture(error, operation: "subscription.authorization")
            subscriptionManager.showAuthorizationFailure()
            if receivedCredentials, attempt?.isPendingRotation == true {
                await removeStaleDNSAfterFailedCredentialCommit()
            }
            await refreshStatus()
        }
    }

    private func removeStaleDNSAfterFailedCredentialCommit() async {
        do {
            try await dnsSettingsManager.remove()
        } catch {
            AdlessSentry.capture(error, operation: "dns.settings.remove_after_credential_commit_failure")
            isManualDisableAlertPresented = true
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
        guard state.isSystemEnabled || state == .disabled else { return }
        do {
            try await dnsSettingsManager.remove()
            await refreshStatus()
        } catch {
            AdlessSentry.capture(error, operation: "dns.settings.remove")
            await refreshStatus()
            isManualDisableAlertPresented = true
        }
    }
}

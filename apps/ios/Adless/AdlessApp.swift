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
    @Published var statusText: String = "Desativado"
    @Published private(set) var hasSubscription = false
    @Published var isSubscriptionPresented = false

    private let blocklistManager = BlocklistManager()
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
        Task {
            await applicationDidBecomeActive()
        }
    }

    var blockedCount: Int {
        blocklistManager.cachedCount
    }

    @MainActor
    func toggle() async {
        guard hasSubscription else {
            isSubscriptionPresented = true
            return
        }

        do {
            if isOn {
                try await vpnManager.stop()
            } else {
                _ = try blocklistManager.ensureActiveBlocklist()
                try await vpnManager.start()
            }
            await refreshStatus()
        } catch {
            statusText = "Não foi possível alterar o bloqueio"
        }
    }

    @MainActor
    func refreshStatus() async {
        let state = await vpnManager.currentStatus()
        isOn = hasSubscription && (state == .connected || state == .connecting)
        if !hasSubscription {
            statusText = "Assinatura necessária"
            return
        }
        switch state {
        case .invalid: statusText = "Inválido"
        case .disconnected: statusText = "Desativado"
        case .connecting: statusText = "Conectando"
        case .connected: statusText = "Ativo"
        case .reasserting: statusText = "Restabelecendo"
        case .disconnecting: statusText = "Desconectando"
        @unknown default: statusText = "Desconhecido"
        }
    }

    @MainActor
    func applicationDidBecomeActive() async {
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

    @MainActor
    private func disableIfSubscriptionExpired() async {
        guard !hasSubscription else { return }
        let state = await vpnManager.currentStatus()
        guard state == .connected || state == .connecting else { return }
        try? await vpnManager.stop()
        isOn = false
        statusText = "Assinatura necessária"
    }
}

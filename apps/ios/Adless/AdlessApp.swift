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
    @Published var blockedCount: Int = 0
    @Published var isUpdating: Bool = false
    @Published var availableSources: [BlocklistSource]
    @Published var whitelist: [String]

    private let blocklistManager = BlocklistManager()
    private let vpnManager = VPNManager()
    private let whitelistStore = WhitelistStore()

    init() {
        availableSources = BlocklistSource.defaultSources()
        whitelist = whitelistStore.entries.map { $0.domain }
        Task {
            await refreshStatus()
            await loadBlocklistCount()
        }
    }

    @MainActor
    func toggle() async {
        do {
            if isOn {
                try await vpnManager.stop()
            } else {
                try await ensureBlocklists()
                try await vpnManager.start()
            }
            await refreshStatus()
        } catch {
            statusText = "Erro: \(error.localizedDescription)"
        }
    }

    @MainActor
    func refreshStatus() async {
        let state = await vpnManager.currentStatus()
        isOn = state == .connected || state == .connecting
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
    func updateBlocklists() async {
        guard !isUpdating else { return }
        isUpdating = true
        do {
            let enabled = availableSources.filter { $0.isEnabled }
            blockedCount = try await blocklistManager.updateBlocklists(sources: enabled)
            await vpnManager.reloadProviderBlocklist()
        } catch {
            statusText = "Erro ao atualizar listas: \(error.localizedDescription)"
        }
        isUpdating = false
    }

    @MainActor
    func addWhitelist(domain: String) {
        whitelistStore.add(domain: domain)
        whitelist = whitelistStore.entries.map { $0.domain }
    }

    @MainActor
    func removeWhitelist(at offsets: IndexSet) {
        for index in offsets {
            let domain = whitelist[index]
            whitelistStore.remove(domain: domain)
        }
        whitelist = whitelistStore.entries.map { $0.domain }
    }

    private func ensureBlocklists() async throws {
        if blocklistManager.cachedCount == 0 {
            _ = try await blocklistManager.updateBlocklists(sources: availableSources.filter { $0.isEnabled })
        }
    }

    private func loadBlocklistCount() async {
        blockedCount = blocklistManager.cachedCount
    }
}

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

    private let blocklistManager = BlocklistManager()
    private let vpnManager = VPNManager()

    init() {
        Task {
            await refreshStatus()
            let result = await blocklistManager.refreshIfNeeded()
            if case .updated = result, isOn {
                await vpnManager.reloadProviderBlocklist()
            }
        }
    }

    var blockedCount: Int {
        blocklistManager.cachedCount
    }

    @MainActor
    func toggle() async {
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
    func applicationDidBecomeActive() async {
        await refreshStatus()
        let result = await blocklistManager.refreshIfNeeded()
        if case .updated = result, isOn {
            await vpnManager.reloadProviderBlocklist()
        }
    }
}

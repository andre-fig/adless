import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                AdlessLogoView(size: 88)

                Button {
                    if viewModel.hasSubscription {
                        Task { await viewModel.toggle() }
                    } else {
                        viewModel.isSubscriptionPresented = true
                    }
                } label: {
                    Image(systemName: viewModel.hasSubscription
                          ? (viewModel.isOn ? "shield.fill" : "shield")
                          : "lock.shield")
                        .font(.system(size: 56, weight: .medium))
                        .frame(width: 144, height: 144)
                        .foregroundStyle(viewModel.isOn ? .white : .primary)
                        .background(viewModel.isOn ? Color.green : Color.secondary.opacity(0.14))
                        .clipShape(Circle())
                }
                .accessibilityLabel(viewModel.hasSubscription
                                    ? (viewModel.isOn ? "Desativar bloqueio" : "Ativar bloqueio")
                                    : "Assinar para ativar o bloqueio")
                .accessibilityHint(viewModel.hasSubscription
                                   ? "Ativa ou desativa o bloqueio DNS"
                                   : "Abre as opções de assinatura")

                Text(viewModel.statusText)
                    .font(.headline)
                    .foregroundStyle(viewModel.isOn ? .green : .secondary)

                Spacer()
            }
            .padding()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.applicationDidBecomeActive() }
        }
        .sheet(isPresented: $viewModel.isSubscriptionPresented) {
            SubscriptionView(manager: viewModel.subscriptionManager)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: AppViewModel())
    }
}

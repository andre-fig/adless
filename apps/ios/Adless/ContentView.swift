import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

                Button {
                    Task { await viewModel.toggle() }
                } label: {
                    Image(systemName: viewModel.isOn ? "shield.fill" : "shield")
                        .font(.system(size: 56, weight: .medium))
                        .frame(width: 144, height: 144)
                        .foregroundStyle(viewModel.isOn ? .white : .primary)
                        .background(viewModel.isOn ? Color.green : Color.secondary.opacity(0.14))
                        .clipShape(Circle())
                }
                .accessibilityLabel(viewModel.isOn ? "Desativar bloqueio" : "Ativar bloqueio")
                .accessibilityHint("Ativa ou desativa o bloqueio DNS")

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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: AppViewModel())
    }
}

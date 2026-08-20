import StoreKit
import SwiftUI

struct SubscriptionView: View {
    @ObservedObject var manager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)

                    Text("Proteja sua navegação")
                        .font(.title2.weight(.semibold))

                    Text("O Adless bloqueia anúncios e rastreadores diretamente no aparelho.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        ForEach(manager.products, id: \.id) { product in
                            Button {
                                Task { await manager.purchase(product) }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(product.displayName)
                                            .font(.headline)
                                        Spacer()
                                        Text(product.displayPrice)
                                            .font(.headline)
                                    }
                                    Text(product.description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if product.subscription?.introductoryOffer != nil {
                                        Text("7 dias grátis para novos assinantes")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if manager.products.isEmpty {
                        Text("As opções de assinatura estarão disponíveis em breve.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button("Restaurar compras") {
                        Task { await manager.restorePurchases() }
                    }
                    .disabled(manager.isProcessing)

                    Text("A assinatura é renovada automaticamente até ser cancelada. O pagamento é processado pela App Store.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Assinatura")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .overlay {
                if manager.isProcessing {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Assinatura", isPresented: Binding(
                get: { manager.message != nil },
                set: { if !$0 { manager.clearMessage() } }
            )) {
                Button("OK") { manager.clearMessage() }
            } message: {
                Text(manager.message ?? "")
            }
        }
    }
}

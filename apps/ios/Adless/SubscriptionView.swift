import StoreKit
import SwiftUI

struct SubscriptionView: View {
    @ObservedObject var manager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AdlessLogoView(size: 96)

                    Text("Protect your browsing")
                        .font(.title2.weight(.semibold))

                    Text("Adless blocks ads and trackers directly on your device.")
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
                                        Text("7 days free for new subscribers")
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
                        Text("Subscription options will be available soon.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button("Restore Purchases") {
                        Task { await manager.restorePurchases() }
                    }
                    .disabled(manager.isProcessing)

                    Text("Your subscription renews automatically until canceled. Payment is processed by the App Store.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Subscription")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
            .alert("Subscription", isPresented: Binding(
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

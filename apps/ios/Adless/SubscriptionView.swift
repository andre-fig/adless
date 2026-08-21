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
                                    if let offer = product.subscription?.introductoryOffer,
                                       let offerText = SubscriptionOfferFormatter.freeTrialText(for: offer) {
                                        Text(offerText)
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

                    Text("Your subscription renews automatically until canceled. Payment is processed by the App Store.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        HStack {
                            Button("Restore Purchase") {
                                Task { await manager.restorePurchases() }
                            }
                            .disabled(manager.isProcessing)

                            Spacer()

                            Link("Terms of Use", destination: AdlessLegalLinks.terms)
                        }

                        Link("Privacy Policy", destination: AdlessLegalLinks.privacy)
                    }
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Browse cleaner with Adless")
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text("Block ads and trackers with one tap.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .accessibilityElement(children: .combine)
                }

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

private enum AdlessLegalLinks {
    static let terms = URL(string: "https://andre-fig.github.io/adless/terms")!
    static let privacy = URL(string: "https://andre-fig.github.io/adless/privacy")!
}

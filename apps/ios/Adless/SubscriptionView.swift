import StoreKit
import SwiftUI

struct SubscriptionView: View {
    @ObservedObject var manager: SubscriptionManager
    @State private var selectedProductID: String?

    private var orderedProducts: [Product] {
        manager.products.sorted {
            planSortIndex(for: $0) < planSortIndex(for: $1)
        }
    }

    private var selectedProduct: Product? {
        let productID = selectedProductID ?? orderedProducts.first?.id
        return orderedProducts.first { $0.id == productID }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Browse cleaner with Adless")
                            .font(.title2.weight(.semibold))

                        Text("Block ads and trackers with one tap.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cleaner, distraction-free browsing")
                        Text("Fewer tracking requests")
                        Text("Works quietly in the background")
                        Text("No account required")
                    }
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 12) {
                        ForEach(orderedProducts, id: \.id) { product in
                            let isSelected = selectedProduct?.id == product.id

                            Button {
                                selectedProductID = product.id
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(planName(for: product))
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

                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(planName(for: product))
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        }
                    }

                    if let selectedProduct {
                        Button {
                            Task { await manager.purchase(selectedProduct) }
                        } label: {
                            Text(selectedProduct.subscription?.introductoryOffer == nil ? "Continue" : "Start Free Trial")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(manager.isProcessing)
                    }

                    if manager.products.isEmpty {
                        Text("Subscription options will be available soon.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("Payment will be charged after the 7-day free trial. The subscription renews automatically unless canceled at least 24 hours before the end of the current period.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        HStack(spacing: 18) {
                            Button("Restore Purchase") {
                                Task { await manager.restorePurchases() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .disabled(manager.isProcessing)
                            .foregroundStyle(Color(uiColor: .systemBlue))

                            Link("Terms of Use", destination: AdlessLegalLinks.terms)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(uiColor: .systemBlue))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        Link("Privacy Policy", destination: AdlessLegalLinks.privacy)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .systemBlue))
                    }
                }
                .padding()
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

    private func planName(for product: Product) -> String {
        switch product.id {
        case SubscriptionConfiguration.yearlyProductID:
            return "Annual"
        case SubscriptionConfiguration.monthlyProductID:
            return "Monthly"
        default:
            return product.displayName
        }
    }

    private func planSortIndex(for product: Product) -> Int {
        switch product.id {
        case SubscriptionConfiguration.yearlyProductID:
            return 0
        case SubscriptionConfiguration.monthlyProductID:
            return 1
        default:
            return 2
        }
    }
}

private enum AdlessLegalLinks {
    static let terms = URL(string: "https://andre-fig.github.io/adless/terms")!
    static let privacy = URL(string: "https://andre-fig.github.io/adless/privacy")!
}

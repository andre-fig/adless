import SwiftUI

struct SubscriptionView: View {
    @ObservedObject var manager: SubscriptionManager
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    @State private var selectedProductID: String?

    private let benefits = [
        "Cleaner, distraction-free browsing",
        "Fewer tracking requests",
        "Works quietly in the background",
        "No account required"
    ]

    private var orderedOptions: [SubscriptionOption] {
        manager.options.sorted {
            planSortIndex(for: $0.id) < planSortIndex(for: $1.id)
        }
    }

    private var selectedOption: SubscriptionOption? {
        let optionID = selectedProductID ?? orderedOptions.first?.id
        return orderedOptions.first { $0.id == optionID }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Browse cleaner with Adless")
                            .font(.title2.weight(.semibold))

                        Text("Block ads and trackers with one tap.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(benefits, id: \.self) { benefit in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)

                                Text(benefit)
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 20) {
                        ForEach(orderedOptions) { option in
                            let isSelected = selectedOption?.id == option.id

                            Button {
                                selectedProductID = option.id
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(option.name)
                                                .font(.headline)
                                            Spacer()
                                            Text(option.displayPrice)
                                                .font(.headline)
                                        }
                                        Text(option.description)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        if let offerText = option.freeTrialText {
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
                            .accessibilityLabel(option.name)
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        }
                    }

                    if let selectedOption {
                        Button {
                            Task { await manager.purchase(selectedOption) }
                        } label: {
                            Text(selectedOption.freeTrialText == nil ? "Continue" : "Start Free Trial")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(manager.isProcessing)
                    }

                    if manager.options.isEmpty {
                        Text("Subscription options will be available soon.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 4)
                    }

                    Text("Payment will be charged after the 7-day free trial. The subscription renews automatically unless canceled at least 24 hours before the end of the current period.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 22) {
                        HStack(spacing: 22) {
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
                .padding(.horizontal, 20)
                .padding(.vertical)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: SubscriptionContentHeightKey.self,
                                value: proxy.size.height
                            )
                    }
                }
            }
            .onPreferenceChange(SubscriptionContentHeightKey.self, perform: onContentHeightChange)
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
        .background(Color(.systemBackground))
    }

    private func planSortIndex(for productID: String) -> Int {
        switch productID {
        case SubscriptionConfiguration.yearlyProductID:
            return 0
        case SubscriptionConfiguration.monthlyProductID:
            return 1
        default:
            return 2
        }
    }
}

private struct SubscriptionContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum AdlessLegalLinks {
    static let terms = URL(string: "https://andre-fig.github.io/adless/terms")!
    static let privacy = URL(string: "https://andre-fig.github.io/adless/privacy")!
}

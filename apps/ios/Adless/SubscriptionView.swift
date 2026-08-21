import SwiftUI

enum AdlessTheme {
    static let subscriptionDrawerBackground = Color(red: 0.92, green: 0.93, blue: 0.95)
    static let selectedPlanBackground = Color(red: 0.93, green: 0.95, blue: 1.0)
}

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

    private let adlessBlue = Color(red: 0.0, green: 0.32, blue: 0.78)
    private let mutedTextColor = Color(red: 0.40, green: 0.41, blue: 0.44)

    private var orderedOptions: [SubscriptionOption] {
        manager.options.sorted {
            planSortIndex(for: $0.id) < planSortIndex(for: $1.id)
        }
    }

    private var selectedOption: SubscriptionOption? {
        let optionID = selectedProductID ?? orderedOptions.first?.id
        return orderedOptions.first { $0.id == optionID }
    }

    private var annualSavingsPercent: Int? {
        guard let annual = orderedOptions.first(where: { $0.id == SubscriptionConfiguration.yearlyProductID }),
              let monthly = orderedOptions.first(where: { $0.id == SubscriptionConfiguration.monthlyProductID }) else {
            return nil
        }

        let monthlyAnnualPrice = monthly.price * Decimal(12)
        guard monthlyAnnualPrice > 0, annual.price < monthlyAnnualPrice else { return nil }

        let savings = (monthlyAnnualPrice - annual.price) / monthlyAnnualPrice * Decimal(100)
        return max(0, Int(NSDecimalNumber(decimal: savings).doubleValue.rounded()))
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
                VStack(spacing: 28) {
                    VStack(spacing: 24) {
                        VStack(spacing: 26) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Browse cleaner with Adless")
                                .font(.title2.weight(.semibold))

                            Text("Block ads and trackers with one tap.")
                                .font(.subheadline)
                                .foregroundStyle(mutedTextColor)
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
                    }

                        VStack(spacing: 18) {
                        VStack(spacing: 14) {
                            ForEach(orderedOptions) { option in
                                let isSelected = selectedOption?.id == option.id

                                Button {
                                    selectedProductID = option.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        HStack(alignment: .center, spacing: 12) {
                                            Text(option.name)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()

                                            HStack(alignment: .center, spacing: 12) {
                                                Text(option.displayPrice)
                                                    .font(.subheadline.weight(.semibold))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.85)
                                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                    .font(.body)
                                                    .foregroundStyle(isSelected ? adlessBlue : Color.secondary)
                                            }
                                            .padding(.top, 7)
                                        }

                                        Text(option.description)
                                            .font(.footnote)
                                            .foregroundStyle(mutedTextColor)
                                            .padding(.top, 0)
                                        if !option.renewalText.isEmpty {
                                            Text(option.renewalText)
                                                .font(.caption)
                                                .foregroundStyle(mutedTextColor)
                                                .padding(.top, 9)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(isSelected ? AdlessTheme.selectedPlanBackground : Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(isSelected ? adlessBlue : .clear, lineWidth: 2)
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        if option.id == SubscriptionConfiguration.yearlyProductID,
                                           let annualSavingsPercent {
                                            Text("Best Value · Save \(annualSavingsPercent)%")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(adlessBlue)
                                                .clipShape(Capsule())
                                                .offset(x: -16, y: -18)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.name)
                                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                            }
                        }

                        if let selectedOption {
                            VStack(spacing: 8) {
                                Button {
                                    Task { await manager.purchase(selectedOption) }
                                } label: {
                                    Text("Start 7-Day Free Trial")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .tint(adlessBlue)
                                .disabled(manager.isProcessing)

                                Text("Cancel anytime.")
                                    .font(.caption)
                                    .foregroundStyle(mutedTextColor)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        }
                    }

                    if manager.options.isEmpty {
                        Text("Subscription options will be available soon.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 4)
                    }

                    Text("Payment will be charged after the 7-day free trial. The subscription renews automatically unless canceled at least 24 hours before the end of the current period.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(mutedTextColor)
                        .padding(.top, -12)

                    VStack(spacing: 22) {
                        HStack(spacing: 22) {
                            Button("Restore Purchase") {
                                Task { await manager.restorePurchases() }
                            }
                            .font(.footnote.weight(.semibold))
                            .disabled(manager.isProcessing)
                            .foregroundStyle(adlessBlue)

                            Link("Terms of Use", destination: AdlessLegalLinks.terms)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(adlessBlue)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        Link("Privacy Policy", destination: AdlessLegalLinks.privacy)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(adlessBlue)
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
        .background(AdlessTheme.subscriptionDrawerBackground)
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

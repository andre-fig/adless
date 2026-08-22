import SwiftUI
import UIKit

enum AdlessTheme {
    static let subscriptionDrawerBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.102, green: 0.122, blue: 0.149, alpha: 1)
            : UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1)
    })
    static let selectedPlanBackground = Color(red: 0.93, green: 0.95, blue: 1.0)
}

struct SubscriptionView: View {
    @ObservedObject var manager: SubscriptionManager
    @Environment(\.colorScheme) private var colorScheme
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    @State private var selectedProductID: String?
    @State private var presentedLegalDocument: AdlessLegalDocument?

    private let benefits = [
        "Cleaner, distraction-free browsing",
        "Fewer tracking requests",
        "Works quietly in the background",
        "No account required"
    ]

    private let adlessBlue = Color(red: 0.0, green: 0.32, blue: 0.78)
    private var mutedTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.58, green: 0.60, blue: 0.66)
            : Color(red: 0.40, green: 0.41, blue: 0.44)
    }

    private var planBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.125, green: 0.145, blue: 0.18)
            : .white
    }

    private var selectedPlanCardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.153, green: 0.192, blue: 0.251)
            : AdlessTheme.selectedPlanBackground
    }

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
                                    .background(isSelected ? selectedPlanCardBackground : planBackground)
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
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
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

                            Button("Terms of Use") {
                                presentedLegalDocument = .terms
                            }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(adlessBlue)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        Button("Privacy Policy") {
                            presentedLegalDocument = .privacy
                        }
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
        .overlay {
            if let presentedLegalDocument {
                NavigationStack {
                    AdlessLegalDocumentView(document: presentedLegalDocument) {
                        self.presentedLegalDocument = nil
                    }
                }
                .background(AdlessTheme.subscriptionDrawerBackground)
            }
        }
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

private enum AdlessLegalDocument: Hashable {
    case terms
    case privacy

    var title: String {
        switch self {
        case .terms:
            return "Terms of Use"
        case .privacy:
            return "Privacy Policy"
        }
    }

    var lastUpdated: String {
        "Last updated: August 20, 2026"
    }

    var introduction: String {
        switch self {
        case .terms:
            return "These Terms of Use govern your use of Adless, an on-device DNS filtering application developed by Orbe Works."
        case .privacy:
            return "Adless is developed by Orbe Works. This Privacy Policy explains what happens when you use the Adless iOS app and website."
        }
    }

    var sections: [AdlessLegalSection] {
        switch self {
        case .terms:
            return [
                AdlessLegalSection(
                    title: "Subscriptions",
                    body: "Adless may be offered through monthly and annual auto-renewable subscriptions. A subscription includes the features shown in the app at the time of purchase. Any free trial, price, renewal date, and applicable taxes are displayed by Apple before purchase.\n\nPayment is charged to your Apple Account. Unless canceled through your Apple Account settings at least 24 hours before the end of the current period, a subscription renews automatically. Apple manages billing, refunds, and cancellation."
                ),
                AdlessLegalSection(
                    title: "Use of the service",
                    body: "Adless provides local DNS-based blocking of domains identified by its blocklist. No filtering system can identify every ad, tracker, or domain, and blocking a domain can occasionally affect a website or app. You are responsible for deciding whether to keep the protection enabled."
                ),
                AdlessLegalSection(
                    title: "Availability",
                    body: "We may update the blocklist, app, or service to improve reliability and security. The app keeps a valid local list and can continue using it when the network is unavailable, but uninterrupted operation cannot be guaranteed."
                )
            ]
        case .privacy:
            return [
                AdlessLegalSection(
                    title: "What Adless does",
                    body: "Adless uses Apple’s Network Extension DNS Proxy to process DNS queries on your device and block domains included in the active blocklist. DNS queries are handled locally by the app and are not sent to an Orbe Works server or a remote VPN service."
                ),
                AdlessLegalSection(
                    title: "Information we collect",
                    body: "Orbe Works does not collect account information, browsing history, DNS query history, device identifiers, advertising identifiers, analytics, or payment information through Adless. The app has no account, login, or custom backend. Blocking statistics are stored locally in the app’s protected storage."
                ),
                AdlessLegalSection(
                    title: "Third parties",
                    body: "Apple processes App Store purchases and subscriptions under Apple’s own terms and privacy policy. Adless downloads public, static blocklist files from GitHub Pages. Those requests can include standard technical connection information handled by the hosting provider, such as an IP address."
                ),
                AdlessLegalSection(
                    title: "Data retention",
                    body: "Adless does not maintain a user account or server-side user record. Local blocklists, subscription state, and blocking statistics can be removed by deleting the app. Apple manages purchase records and subscription history."
                ),
                AdlessLegalSection(
                    title: "Children",
                    body: "Adless is not directed at children and does not knowingly collect personal information from children."
                )
            ]
        }
    }

    var contactText: String {
        "For support, contact a_figueiredo@icloud.com."
    }
}

private struct AdlessLegalSection: Identifiable {
    let title: String
    let body: String

    var id: String { title }
}

private struct AdlessLegalDocumentView: View {
    let document: AdlessLegalDocument
    let onBack: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var mutedTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.66, green: 0.68, blue: 0.73)
            : Color(red: 0.40, green: 0.41, blue: 0.44)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(document.lastUpdated)
                    .font(.caption)
                    .foregroundStyle(mutedTextColor)

                Text(document.introduction)
                    .font(.body)

                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)

                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(mutedTextColor)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Contact")
                        .font(.headline)

                    Text(document.contactText)
                        .font(.body)
                        .foregroundStyle(mutedTextColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(AdlessTheme.subscriptionDrawerBackground)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .foregroundStyle(Color(red: 0.0, green: 0.32, blue: 0.78))
            }
        }
    }
}

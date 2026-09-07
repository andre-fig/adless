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

    private var benefits: [String] {
        [
            String(localized: "Cleaner, distraction-free browsing"),
            String(localized: "Fewer tracking requests"),
            String(localized: "Works quietly in the background"),
            String(localized: "No account required")
        ]
    }

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
        return max(0, Int(NSDecimalNumber(decimal: savings).doubleValue.rounded(.down)))
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

                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.body)
                                                .foregroundStyle(isSelected ? adlessBlue : Color.secondary)
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
                                            Text(
                                                String(
                                                    format: String(localized: "Best Value · Save %d%%", defaultValue: "Best Value · Save %d%%"),
                                                    annualSavingsPercent
                                                )
                                            )
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(adlessBlue)
                                                .clipShape(Capsule())
                                                .offset(x: -16, y: -12)
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
                                    Text(
                                        selectedOption.hasFreeTrial
                                            ? String(localized: "Start 7-Day Free Trial")
                                            : String(localized: "Subscribe now")
                                    )
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

                    if let selectedOption {
                        Text(
                            selectedOption.hasFreeTrial
                                ? String(localized: "Payment will be charged after the 7-day free trial. The subscription renews automatically unless canceled at least 24 hours before the end of the current period.")
                                : String(localized: "Payment will be charged when you confirm the purchase. The subscription renews automatically unless canceled at least 24 hours before the end of the current period.")
                        )
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(mutedTextColor)
                            .padding(.top, -12)
                    }

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
            return String(localized: "Terms of Use")
        case .privacy:
            return String(localized: "Privacy Policy")
        }
    }

    var lastUpdated: String {
        String(localized: "Last updated: August 26, 2026")
    }

    var introduction: String {
        switch self {
        case .terms:
            return String(localized: "These Terms of Use govern your use of Adless, a DNS filtering application developed by Orbe Works.")
        case .privacy:
            return String(localized: "Adless is developed by Orbe Works. This Privacy Policy explains what happens when you use the Adless iOS app and website.")
        }
    }

    var sections: [AdlessLegalSection] {
        switch self {
        case .terms:
            return [
                AdlessLegalSection(
                    id: "subscriptions",
                    title: String(localized: "Subscriptions"),
                    body: String(localized: "Adless may be offered through monthly and annual auto-renewable subscriptions. A subscription includes the features shown in the app at the time of purchase. Any free trial, price, renewal date, and applicable taxes are displayed by Apple before purchase.\n\nPayment is charged to your Apple Account. Unless canceled through your Apple Account settings at least 24 hours before the end of the current period, a subscription renews automatically. Apple manages billing, refunds, and cancellation.")
                ),
                AdlessLegalSection(
                    id: "use_of_service",
                    title: String(localized: "Use of the service"),
                    body: String(localized: "Adless provides DNS-based blocking of domains identified by its blocklist. No filtering system can identify every ad, tracker, or domain, and blocking a domain can occasionally affect a website or app. You are responsible for deciding whether to keep the protection enabled.")
                ),
                AdlessLegalSection(
                    id: "availability",
                    title: String(localized: "Availability"),
                    body: String(localized: "Adless may update the blocklist, app, or service to improve reliability and security. DNS protection depends on the saved iOS configuration and network availability, but uninterrupted operation cannot be guaranteed.")
                )
            ]
        case .privacy:
            return [
                AdlessLegalSection(
                    id: "what_adless_does",
                    title: String(localized: "What Adless does"),
                    body: String(localized: "Adless configures Apple encrypted DNS settings. DNS queries go over HTTPS to the Adless DNS service, where the active blocklist is applied before permitted queries are resolved by Cloudflare DNS or Quad9. Web traffic does not pass through Adless, and no account is required.")
                ),
                AdlessLegalSection(
                    id: "information_we_collect",
                    title: String(localized: "Information we collect"),
                    body: String(localized: "Orbe Works does not collect or retain account information, browsing history, DNS query history, advertising identifiers, or payment information through Adless. The app has no account or login. The service stores only an aggregate blocked total associated with an internal installation identifier and one-way hashes of device-bound credentials; it does not store domains, DNS packets, or an application-level history. Because a DoH GET can carry the DNS wire message in the URL and the dns-token is part of the endpoint path, Cloudflare may process technical request metadata under its infrastructure and logging systems; Adless does not enable application-level request logging or send these values to Sentry. Permitted DNS queries are transmitted to Cloudflare DNS or Quad9 only to obtain DNS answers under their own policies. Adless uses Sentry for crash and performance diagnostics, but does not send DNS queries, domain names, browsing history, or either credential to it.")
                ),
                AdlessLegalSection(
                    id: "third_parties",
                    title: String(localized: "Third parties"),
                    body: String(localized: "Apple processes App Store purchases and subscriptions under Apple’s own terms and privacy policy. Cloudflare provides infrastructure for the Adless edge service. Cloudflare DNS and Quad9 process permitted DNS-over-HTTPS queries to return DNS answers under their respective service and privacy policies. Sentry processes crash and performance diagnostics for reliability. Adless does not sell data or use DNS queries for advertising.")
                ),
                AdlessLegalSection(
                    id: "data_retention",
                    title: String(localized: "Data retention"),
                    body: String(localized: "Adless does not maintain a user account or domain history. The app stores the last known aggregate counter locally; the service stores aggregate totals associated with an internal installation identifier and does not maintain query history. The device-bound Keychain credentials may remain in the Keychain after uninstall on the same device; they are not migrated to a new device. This version has no credential-deletion endpoint. Apple manages purchase records and subscription history.")
                ),
                AdlessLegalSection(
                    id: "children",
                    title: String(localized: "Children"),
                    body: String(localized: "Adless is not directed at children and does not knowingly collect personal information from children.")
                )
            ]
        }
    }

    var contactText: String {
        String(localized: "For support, contact a_figueiredo@icloud.com.")
    }
}

private struct AdlessLegalSection: Identifiable {
    let id: String
    let title: String
    let body: String
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
            .padding(.top, 6)
            .padding(.bottom, 24)
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

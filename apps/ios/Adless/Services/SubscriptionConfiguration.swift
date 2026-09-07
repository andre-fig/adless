import Foundation
import StoreKit

enum SubscriptionConfiguration {
    static let monthlyProductID = "com.orbeworks.adless.pro.monthly"
    static let yearlyProductID = "com.orbeworks.adless.pro.yearly"

    static let productIDs = [
        monthlyProductID,
        yearlyProductID
    ]

    static let subscriptionDirectoryName = "Subscription"
    static let subscriptionStateFileName = "subscription-state.json"

#if DEBUG && os(iOS) && targetEnvironment(simulator)
    // Direct simulator launches do not have Xcode's StoreKit test session. These
    // display-only options keep the subscription drawer usable for UI work;
    // purchases still require Product instances supplied by StoreKit.
    static let simulatorOptions = [
        SubscriptionOption(
            id: yearlyProductID,
            name: String(localized: "Annual"),
            price: Decimal(string: "29.90")!,
            description: SubscriptionOfferFormatter.trialDurationText(value: 7, unit: .day) + " · " + SubscriptionOfferFormatter.monthlyEquivalentText(displayPrice: simulatorPrice(Decimal(string: "2.49")!)),
            renewalText: SubscriptionOfferFormatter.renewalText(displayPrice: simulatorPrice(Decimal(string: "29.90")!), isAnnual: true, hasFreeTrial: true),
            hasFreeTrial: true,
            product: nil
        ),
        SubscriptionOption(
            id: monthlyProductID,
            name: String(localized: "Monthly"),
            price: Decimal(string: "4.90")!,
            description: String(localized: "Charged immediately · Cancel anytime"),
            renewalText: SubscriptionOfferFormatter.renewalText(displayPrice: simulatorPrice(Decimal(string: "4.90")!), isAnnual: false, hasFreeTrial: false),
            hasFreeTrial: false,
            product: nil
        )
    ]

    private static func simulatorPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ 0,00"
    }
#endif
}

struct SubscriptionOption: Identifiable {
    let id: String
    let name: String
    let price: Decimal
    let description: String
    let renewalText: String
    let hasFreeTrial: Bool
    let product: Product?
}

enum SubscriptionOfferFormatter {
    static func monthlyEquivalentText(displayPrice: String) -> String {
        String(
            format: String(localized: "annual_monthly_price_format", defaultValue: "Equivalent to %@/mo"),
            priceText(displayPrice)
        )
    }

    static func renewalText(displayPrice: String, isAnnual: Bool, hasFreeTrial: Bool) -> String {
        let format: String
        if isAnnual {
            format = hasFreeTrial
                ? String(localized: "Then %@ billed annually.")
                : String(localized: "%@ billed annually.")
        } else {
            format = hasFreeTrial
                ? String(localized: "Then %@ billed monthly.")
                : String(localized: "%@ billed monthly.")
        }
        return String(format: format, priceText(displayPrice))
    }

    private static func priceText(_ displayPrice: String) -> String {
        guard displayPrice.hasPrefix("R$") else { return displayPrice }
        return "R$" + displayPrice.dropFirst(2).trimmingCharacters(in: .whitespaces)
    }

    static func trialDurationText(for offer: Product.SubscriptionOffer) -> String? {
        guard offer.paymentMode == .freeTrial else { return nil }
        return trialDurationText(value: offer.period.value, unit: offer.period.unit)
    }

    static func trialDurationText(
        value: Int,
        unit: Product.SubscriptionPeriod.Unit
    ) -> String {
        if unit == .week && value == 1 {
            return trialDurationText(value: 7, unit: .day)
        }

        let unitName: String
        switch unit {
        case .day:
            unitName = String(localized: value == 1 ? "day" : "days")
        case .week:
            unitName = String(localized: value == 1 ? "week" : "weeks")
        case .month:
            unitName = String(localized: value == 1 ? "month" : "months")
        case .year:
            unitName = String(localized: value == 1 ? "year" : "years")
        @unknown default:
            unitName = String(localized: value == 1 ? "period" : "periods")
        }

        return String(
            format: String(localized: "free_trial_format", defaultValue: "%d %@ free"),
            value,
            unitName
        )
    }

    static func freeTrialText(for offer: Product.SubscriptionOffer) -> String? {
        guard offer.paymentMode == .freeTrial else { return nil }
        return freeTrialText(value: offer.period.value, unit: offer.period.unit)
    }

    static func freeTrialText(
        value: Int,
        unit: Product.SubscriptionPeriod.Unit
    ) -> String {
        let unitName: String
        switch unit {
        case .day:
            unitName = String(localized: value == 1 ? "day" : "days")
        case .week:
            unitName = String(localized: value == 1 ? "week" : "weeks")
        case .month:
            unitName = String(localized: value == 1 ? "month" : "months")
        case .year:
            unitName = String(localized: value == 1 ? "year" : "years")
        @unknown default:
            unitName = String(localized: value == 1 ? "period" : "periods")
        }

        return String(
            format: String(localized: "free_trial_new_subscriber_format", defaultValue: "%d %@ free for new subscribers"),
            value,
            unitName
        )
    }
}

struct SubscriptionAccessSnapshot: Codable, Equatable {
    let isEntitled: Bool
    let productID: String?
    let effectiveUntil: Date?
    let inGracePeriod: Bool
    let lastVerifiedAt: Date

    static func inactive(at date: Date = Date()) -> SubscriptionAccessSnapshot {
        SubscriptionAccessSnapshot(
            isEntitled: false,
            productID: nil,
            effectiveUntil: nil,
            inGracePeriod: false,
            lastVerifiedAt: date
        )
    }
}

enum SubscriptionAccessPolicy {
    static func allowsAccess(_ snapshot: SubscriptionAccessSnapshot, at date: Date = Date()) -> Bool {
        guard snapshot.isEntitled,
              let effectiveUntil = snapshot.effectiveUntil else { return false }
        return effectiveUntil > date
    }
}

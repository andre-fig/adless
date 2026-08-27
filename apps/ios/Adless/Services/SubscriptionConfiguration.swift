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
            displayPrice: String(format: String(localized: "display_price_format", defaultValue: "%@ / %@"), simulatorPrice(Decimal(string: "29.90")!), String(localized: "year")),
            description: String(format: String(localized: "free_trial_format", defaultValue: "%d %@ free"), 7, String(localized: "days")) + " · " + String(format: String(localized: "annual_monthly_price_format", defaultValue: "%@/mo"), simulatorPrice(Decimal(string: "2.49")!)),
            renewalText: String(format: String(localized: "Then %@ per %@.", defaultValue: "Then %@ per %@."), simulatorPrice(Decimal(string: "29.90")!), String(localized: "year")),
            product: nil
        ),
        SubscriptionOption(
            id: monthlyProductID,
            name: String(localized: "Monthly"),
            price: Decimal(string: "4.90")!,
            displayPrice: String(format: String(localized: "display_price_format", defaultValue: "%@ / %@"), simulatorPrice(Decimal(string: "4.90")!), String(localized: "month")),
            description: String(format: String(localized: "free_trial_format", defaultValue: "%d %@ free"), 7, String(localized: "days")),
            renewalText: String(format: String(localized: "Then %@ per %@.", defaultValue: "Then %@ per %@."), simulatorPrice(Decimal(string: "4.90")!), String(localized: "month")),
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
    let displayPrice: String
    let description: String
    let renewalText: String
    let product: Product?
}

enum SubscriptionOfferFormatter {
    static func trialDurationText(for offer: Product.SubscriptionOffer) -> String? {
        guard offer.paymentMode == .freeTrial else { return nil }
        return trialDurationText(value: offer.period.value, unit: offer.period.unit)
    }

    static func trialDurationText(
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

import Foundation
import StoreKit

enum SubscriptionConfiguration {
    static let monthlyProductID = "com.orbeworks.adless.pro.monthly"
    static let yearlyProductID = "com.orbeworks.adless.pro.yearly"

    static let productIDs = [
        monthlyProductID,
        yearlyProductID
    ]

    static let appGroupIdentifier = BlocklistConfiguration.appGroupIdentifier
    static let subscriptionDirectoryName = "Subscription"
    static let subscriptionStateFileName = "subscription-state.json"

#if DEBUG && os(iOS) && targetEnvironment(simulator)
    // Direct simulator launches do not have Xcode's StoreKit test session. These
    // display-only options keep the subscription drawer usable for UI work;
    // purchases still require Product instances supplied by StoreKit.
    static let simulatorOptions = [
        SubscriptionOption(
            id: yearlyProductID,
            name: "Annual",
            displayPrice: "R$ 29.90",
            description: "Adless Pro annual plan.",
            freeTrialText: "7 days free for new subscribers",
            product: nil
        ),
        SubscriptionOption(
            id: monthlyProductID,
            name: "Monthly",
            displayPrice: "R$ 4.90",
            description: "Adless Pro monthly plan.",
            freeTrialText: "7 days free for new subscribers",
            product: nil
        )
    ]
#endif
}

struct SubscriptionOption: Identifiable {
    let id: String
    let name: String
    let displayPrice: String
    let description: String
    let freeTrialText: String?
    let product: Product?
}

enum SubscriptionOfferFormatter {
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
            unitName = value == 1 ? "day" : "days"
        case .week:
            unitName = value == 1 ? "week" : "weeks"
        case .month:
            unitName = value == 1 ? "month" : "months"
        case .year:
            unitName = value == 1 ? "year" : "years"
        @unknown default:
            unitName = value == 1 ? "period" : "periods"
        }

        return "\(value) \(unitName) free for new subscribers"
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

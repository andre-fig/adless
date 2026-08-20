import Foundation

enum SubscriptionConfiguration {
    static let productIDs = [
        "com.orbeworks.adless.pro.monthly",
        "com.orbeworks.adless.pro.yearly"
    ]

    static let introductoryOfferDays = 7
    static let appGroupIdentifier = BlocklistConfiguration.appGroupIdentifier
    static let subscriptionDirectoryName = "Subscription"
    static let subscriptionStateFileName = "subscription-state.json"
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

import Combine
import Foundation
import os.log
import StoreKit

enum SubscriptionManagerState: Equatable {
    case checking
    case active(productID: String, effectiveUntil: Date, inGracePeriod: Bool)
    case inactive
    case unavailable
}

@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var state: SubscriptionManagerState = .checking
    @Published private(set) var isProcessing = false
    @Published private(set) var message: String?

    var onEntitlementChanged: ((Bool) -> Void)?

    private let storage: SubscriptionStorage
    private var transactionUpdatesTask: Task<Void, Never>?

    convenience init() {
        self.init(storage: SubscriptionStorage())
    }

    init(storage: SubscriptionStorage) {
        self.storage = storage
        transactionUpdatesTask = listenForTransactionUpdates()

        if let cached = storage.load(), SubscriptionAccessPolicy.allowsAccess(cached) {
            state = .active(
                productID: cached.productID ?? "",
                effectiveUntil: cached.effectiveUntil ?? Date(),
                inGracePeriod: cached.inGracePeriod
            )
        }

        Task { await loadAndRefresh() }
    }

    var hasActiveEntitlement: Bool {
        if case .active = state { return true }
        return false
    }

    var isInGracePeriod: Bool {
        if case .active(_, _, let inGracePeriod) = state { return inGracePeriod }
        return false
    }

    func loadAndRefresh() async {
        await loadProducts()
        await refreshEntitlement()
    }

    func purchase(_ product: Product) async {
        isProcessing = true
        message = nil
        defer { isProcessing = false }

        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await refreshEntitlement()
            case .success(.unverified):
                message = "Não foi possível verificar a compra"
            case .userCancelled:
                break
            case .pending:
                message = "A compra está aguardando aprovação"
            @unknown default:
                message = "Não foi possível concluir a compra"
            }
        } catch {
            os_log("Subscription purchase failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            message = "Não foi possível concluir a compra"
        }
    }

    func restorePurchases() async {
        isProcessing = true
        message = nil
        defer { isProcessing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            os_log("Subscription restore failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            message = "Não foi possível restaurar as compras"
        }
    }

    func clearMessage() {
        message = nil
    }

    private func loadProducts() async {
        do {
            let loaded = try await Product.products(for: SubscriptionConfiguration.productIDs)
            products = loaded.sorted { lhs, rhs in
                let lhsIndex = SubscriptionConfiguration.productIDs.firstIndex(of: lhs.id) ?? .max
                let rhsIndex = SubscriptionConfiguration.productIDs.firstIndex(of: rhs.id) ?? .max
                return lhsIndex < rhsIndex
            }
            if products.isEmpty { state = .unavailable }
        } catch {
            os_log("Subscription products unavailable: %{public}@", log: .default, type: .error, error.localizedDescription)
            if !hasValidCachedEntitlement() {
                state = .unavailable
            }
        }
    }

    private func refreshEntitlement() async {
        let previousAccess = hasActiveEntitlement
        let now = Date()
        var candidates: [SubscriptionAccessSnapshot] = []
        var receivedStoreStatus = false

        let groupIDs = Set(products.compactMap { $0.subscription?.subscriptionGroupID })
        for groupID in groupIDs {
            do {
                let statuses = try await Product.SubscriptionInfo.status(for: groupID)
                receivedStoreStatus = true
                candidates.append(contentsOf: statuses.compactMap { snapshot(from: $0, now: now) })
            } catch {
                os_log("Subscription status refresh failed: %{public}@", log: .default, type: .error, error.localizedDescription)
            }
        }

        if candidates.isEmpty, let current = await currentEntitlementSnapshot(at: now) {
            candidates.append(current)
            receivedStoreStatus = true
        }

        if let best = candidates.max(by: { ($0.effectiveUntil ?? .distantPast) < ($1.effectiveUntil ?? .distantPast) }) {
            saveAndApply(best)
        } else if !receivedStoreStatus, hasValidCachedEntitlement() {
            // Keep the last verified entitlement during a temporary offline period.
            applyCachedState()
        } else {
            let inactive = SubscriptionAccessSnapshot.inactive(at: now)
            try? storage.save(inactive)
            state = products.isEmpty ? .unavailable : .inactive
            notifyIfAccessChanged(previousAccess)
        }
    }

    private func snapshot(from status: Product.SubscriptionInfo.Status, now: Date) -> SubscriptionAccessSnapshot? {
        guard status.state == .subscribed || status.state == .inGracePeriod,
              case .verified(let transaction) = status.transaction,
              SubscriptionConfiguration.productIDs.contains(transaction.productID),
              transaction.revocationDate == nil,
              case .verified(let renewalInfo) = status.renewalInfo else {
            return nil
        }

        let effectiveUntil: Date?
        if status.state == .inGracePeriod {
            effectiveUntil = renewalInfo.gracePeriodExpirationDate ?? transaction.expirationDate
        } else {
            effectiveUntil = transaction.expirationDate ?? renewalInfo.renewalDate
        }

        guard let effectiveUntil, effectiveUntil > now else { return nil }
        return SubscriptionAccessSnapshot(
            isEntitled: true,
            productID: transaction.productID,
            effectiveUntil: effectiveUntil,
            inGracePeriod: status.state == .inGracePeriod,
            lastVerifiedAt: now
        )
    }

    private func currentEntitlementSnapshot(at now: Date) async -> SubscriptionAccessSnapshot? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  SubscriptionConfiguration.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  let expirationDate = transaction.expirationDate,
                  expirationDate > now else { continue }

            return SubscriptionAccessSnapshot(
                isEntitled: true,
                productID: transaction.productID,
                effectiveUntil: expirationDate,
                inGracePeriod: false,
                lastVerifiedAt: now
            )
        }
        return nil
    }

    private func saveAndApply(_ snapshot: SubscriptionAccessSnapshot) {
        try? storage.save(snapshot)
        let previousAccess = hasActiveEntitlement
        state = .active(
            productID: snapshot.productID ?? "",
            effectiveUntil: snapshot.effectiveUntil ?? Date(),
            inGracePeriod: snapshot.inGracePeriod
        )
        notifyIfAccessChanged(previousAccess)
    }

    private func applyCachedState() {
        guard let cached = storage.load(),
              SubscriptionAccessPolicy.allowsAccess(cached) else {
            state = .inactive
            return
        }
        let previousAccess = hasActiveEntitlement
        state = .active(
            productID: cached.productID ?? "",
            effectiveUntil: cached.effectiveUntil ?? Date(),
            inGracePeriod: cached.inGracePeriod
        )
        notifyIfAccessChanged(previousAccess)
    }

    private func hasValidCachedEntitlement() -> Bool {
        guard let cached = storage.load() else { return false }
        return SubscriptionAccessPolicy.allowsAccess(cached)
    }

    private func notifyIfAccessChanged(_ previousAccess: Bool) {
        guard previousAccess != hasActiveEntitlement else { return }
        onEntitlementChanged?(hasActiveEntitlement)
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self else { return }
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await self.refreshEntitlement()
                case .unverified:
                    os_log("Unverified subscription transaction received", log: .default, type: .error)
                }
            }
        }
    }
}

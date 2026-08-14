import Foundation
import StoreKit
import SwiftUI

/// Reps Pro.
///
/// The free tier is deliberately not a demo: counting works on every engine, free sets are
/// unlimited, the daily-goal plan is free, and the streak and the last 30 days of stats are
/// free forever. That is enough to build the habit, and a habit is what makes the
/// subscription worth anything. Pro is the structure on top — adaptive plans, the published
/// programs, full history, Precision mode, widgets, Health sync, export.
///
/// StoreKit 2 only. No receipt server, no third-party SDK, and no network code anywhere
/// else in the app.
@MainActor
@Observable
final class PurchaseStore {
    static let annualID = "com.gradedays.reps.pro.annual"
    static let monthlyID = "com.gradedays.reps.pro.monthly"
    static let lifetimeID = "com.gradedays.reps.pro.lifetime"

    static let productIDs = [annualID, monthlyID, lifetimeID]

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoading = false
    private(set) var lastError: String?

    /// `nonisolated` only so `deinit` can cancel it. A `deinit` on a main-actor class
    /// cannot touch isolated state, and leaking the listener for the app's lifetime is the
    /// alternative. Plain `nonisolated` rather than `nonisolated(unsafe)`, because `Task`
    /// is already `Sendable` and the unsafe escape hatch buys nothing.
    private nonisolated var updatesTask: Task<Void, Never>?

    func start() async {
        // The listener has to be running before the first entitlement check, or a
        // transaction that lands during launch is missed until the next cold start.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
        await refreshEntitlements()
        await loadProducts()
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // Annual first: it is the recommended option and the one the paywall
            // preselects.
            products = loaded.sorted { lhs, rhs in
                Self.productIDs.firstIndex(of: lhs.id) ?? 0 < Self.productIDs.firstIndex(of: rhs.id) ?? 0
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.productIDs.contains(transaction.productID) else { continue }
            // `revocationDate` covers refunds; `currentEntitlements` already excludes
            // expired subscriptions.
            if transaction.revocationDate == nil { entitled = true }
        }
        isPro = entitled
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        lastError = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "That purchase could not be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return isPro
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro { lastError = "No previous purchase found on this Apple Account." }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// "3 days free, then $29.99/year" — assembled from the product rather than hardcoded,
    /// so it is right in every storefront and currency.
    func priceLine(for product: Product) -> String {
        let price = product.displayPrice
        guard let subscription = product.subscription else { return price }
        let unit = subscription.subscriptionPeriod.unit.localizedLabel
        if let offer = subscription.introductoryOffer, offer.paymentMode == .freeTrial {
            let days = offer.period.value
            let trialUnit = offer.period.unit.localizedLabel
            return "\(days) \(trialUnit)\(days == 1 ? "" : "s") free, then \(price)/\(unit)"
        }
        return "\(price)/\(unit)"
    }
}

private extension Product.SubscriptionPeriod.Unit {
    var localizedLabel: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
    }
}

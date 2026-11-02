import CommerceCore
import Foundation
import StoreKit

public actor StoreKitProvider: PurchaseProvider {
    public let configuration: CommerceConfiguration
    private var products: [String: Product] = [:]

    public init(configuration: CommerceConfiguration) {
        self.configuration = configuration
    }

    public func purchases() async throws -> [VerifiedPurchase] {
        var current: [VerifiedPurchase] = []
        for await result in Transaction.currentEntitlements {
            try Task.checkCancellation()
            guard case .verified(let transaction) = result,
                  transaction.productType == .nonConsumable else { continue }
            current.append(Self.value(transaction))
        }
        var history: [VerifiedPurchase] = []
        for await result in Transaction.all {
            try Task.checkCancellation()
            guard case .verified(let transaction) = result,
                transaction.productType == .nonConsumable,
                  transaction.productID == configuration.trialProductID else { continue }
            history.append(Self.value(transaction))
        }
        return Self.entitlements(configuration: configuration, current: current, history: history)
    }

    public func updates() async -> AsyncStream<VerifiedPurchase> {
        let configuration = configuration
        return AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    guard case .verified(let transaction) = result,
                          transaction.productType == .nonConsumable,
                          transaction.productID == configuration.trialProductID ||
                          transaction.productID == configuration.lifetimeProductID else { continue }
                    let purchase = Self.value(transaction)
                    await transaction.finish()
                    continuation.yield(purchase)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func purchase(productID: String) async throws -> PurchaseResult {
        let product = try await product(for: productID)
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result else {
                throw CommerceError.verificationFailed
            }
            guard transaction.productID == productID,
                transaction.productType == .nonConsumable else { throw CommerceError.unexpectedProduct }
            let purchase = Self.value(transaction)
            await transaction.finish()
            return .purchased(purchase)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            throw CommerceError.providerFailure(message: "Unknown StoreKit purchase result")
        }
    }

    public func restore() async throws {
        try await AppStore.sync()
    }

    public func price(productID: String) async throws -> String? {
        try await product(for: productID).displayPrice
    }

    private func product(for productID: String) async throws -> Product {
        guard productID == configuration.trialProductID || productID == configuration.lifetimeProductID else {
            throw CommerceError.unexpectedProduct
        }
        if let cached = products[productID] { return cached }
        guard let product = try await Product.products(for: [productID]).first,
              product.type == .nonConsumable else {
            throw CommerceError.productUnavailable
        }
        products[productID] = product
        return product
    }

    private static func value(_ transaction: Transaction) -> VerifiedPurchase {
        VerifiedPurchase(
            productID: transaction.productID,
            originalPurchaseDate: transaction.originalPurchaseDate,
            revoked: transaction.revocationDate != nil || transaction.isUpgraded,
            isVerified: true
        )
    }

    static func entitlements(
        configuration: CommerceConfiguration,
        current: [VerifiedPurchase],
        history: [VerifiedPurchase]
    ) -> [VerifiedPurchase] {
        let active = current.filter {
            $0.isVerified && ($0.productID == configuration.lifetimeProductID ||
                $0.productID == configuration.trialProductID)
        }
        let trials = history.filter { $0.isVerified && $0.productID == configuration.trialProductID }
        return active + trials
    }
}
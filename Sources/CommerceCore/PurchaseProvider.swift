import Foundation

public enum PurchaseResult: Sendable, Equatable {
    case purchased(VerifiedPurchase)
    case pending
    case cancelled
}

public enum CommerceError: Error, Sendable, Equatable {
    case verificationFailed
    case unexpectedProduct
    case productUnavailable
    case trialAlreadyUsed
    case alreadyUnlocked
    case providerFailure(message: String)
}

public protocol PurchaseProvider: Sendable {
    func purchases() async throws -> [VerifiedPurchase]
    func updates() async -> AsyncStream<VerifiedPurchase>
    func purchase(productID: String) async throws -> PurchaseResult
    func restore() async throws
    func price(productID: String) async throws -> String?
}

public extension PurchaseProvider {
    func price(productID: String) async throws -> String? { nil }
}

public protocol CommerceClock: Sendable {
    func now() -> Date
    func sleep(until deadline: Date) async throws
}

public struct SystemCommerceClock: CommerceClock {
    public init() {}

    public func now() -> Date { Date() }

    public func sleep(until deadline: Date) async throws {
        let seconds = max(0, deadline.timeIntervalSinceNow)
        try await Task.sleep(for: .seconds(seconds))
    }
}
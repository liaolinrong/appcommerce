import Foundation

public struct CommerceConfiguration: Sendable, Equatable {
    public let trialProductID: String
    public let lifetimeProductID: String
    public let trialDuration: TimeInterval

    public init(
        trialProductID: String,
        lifetimeProductID: String,
        trialDuration: TimeInterval = 15 * 86_400
    ) {
        precondition(!trialProductID.isEmpty && !lifetimeProductID.isEmpty)
        precondition(trialProductID != lifetimeProductID)
        precondition(trialDuration.isFinite && trialDuration > 0)
        self.trialProductID = trialProductID
        self.lifetimeProductID = lifetimeProductID
        self.trialDuration = trialDuration
    }
}

public struct VerifiedPurchase: Sendable, Equatable {
    public let productID: String
    public let originalPurchaseDate: Date
    public let revoked: Bool
    public let isVerified: Bool

    public init(
        productID: String,
        originalPurchaseDate: Date,
        revoked: Bool = false,
        isVerified: Bool
    ) {
        self.productID = productID
        self.originalPurchaseDate = originalPurchaseDate
        self.revoked = revoked
        self.isVerified = isVerified
    }
}

public enum AccessState: Sendable, Equatable {
    case checking
    case notStarted
    case trial(expiresAt: Date)
    case unlocked
    case expired

    public var canEdit: Bool {
        switch self {
        case .trial, .unlocked: true
        case .checking, .notStarted, .expired: false
        }
    }
}

public enum AccessPolicy {
    public static func evaluate(
        configuration: CommerceConfiguration,
        purchases: [VerifiedPurchase],
        now: Date
    ) -> AccessState {
        let verified = purchases.filter(\.isVerified)
        if verified.contains(where: {
            $0.productID == configuration.lifetimeProductID && !$0.revoked
        }) {
            return .unlocked
        }
        let trials = verified.filter { $0.productID == configuration.trialProductID }
        guard let start = trials.map(\.originalPurchaseDate).min() else {
            return .notStarted
        }
        let expiration = start.addingTimeInterval(configuration.trialDuration)
        guard !trials.contains(where: \.revoked), now < expiration else {
            return .expired
        }
        return .trial(expiresAt: expiration)
    }
}
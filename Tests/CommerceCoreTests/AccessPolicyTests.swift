import Foundation
import Testing
@testable import CommerceCore

struct AccessPolicyTests {
    let configuration = CommerceConfiguration(trialProductID: "trial", lifetimeProductID: "lifetime")
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func exactFifteenDayBoundary() {
        let purchase = VerifiedPurchase(productID: "trial", originalPurchaseDate: start, isVerified: true)
        let expiration = start.addingTimeInterval(15 * 86_400)
        #expect(configuration.trialDuration == 1_296_000)
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: [purchase], now: expiration.addingTimeInterval(-0.001)) == .trial(expiresAt: expiration))
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: [purchase], now: expiration) == .expired)
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: [purchase], now: expiration.addingTimeInterval(1)) == .expired)
    }

    @Test func lifetimeTakesPriorityAndRevocationRemovesAccess() {
        let trial = VerifiedPurchase(productID: "trial", originalPurchaseDate: start, revoked: true, isVerified: true)
        let lifetime = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: start, isVerified: true)
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: [trial, lifetime], now: start) == .unlocked)
        let revoked = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: start, revoked: true, isVerified: true)
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: [trial, revoked], now: start) == .expired)
    }

    @Test func ignoresUnverifiedAndUnknownProducts() {
        let fake = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: start, isVerified: false)
        let unrelated = VerifiedPurchase(productID: "other", originalPurchaseDate: start, isVerified: true)
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: [fake, unrelated], now: start) == .notStarted)
    }

    @Test func earliestOriginalDateWins() {
        let early = VerifiedPurchase(productID: "trial", originalPurchaseDate: start, isVerified: true)
        let late = VerifiedPurchase(productID: "trial", originalPurchaseDate: start.addingTimeInterval(86_400), isVerified: true)
        let expiration = start.addingTimeInterval(15 * 86_400)
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: [late, early], now: expiration) == .expired)
    }
}
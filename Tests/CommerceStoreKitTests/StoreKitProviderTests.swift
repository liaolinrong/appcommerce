import CommerceCore
import Foundation
import Testing
@testable import CommerceStoreKit

struct StoreKitProviderTests {
    let configuration = CommerceConfiguration(trialProductID: "trial", lifetimeProductID: "lifetime")
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func trialHistoryKeepsEarliestOriginalDateAndRevocations() {
        let original = VerifiedPurchase(productID: "trial", originalPurchaseDate: start, isVerified: true)
        let restored = VerifiedPurchase(productID: "trial", originalPurchaseDate: start.addingTimeInterval(86_400), isVerified: true)
        let values = StoreKitProvider.entitlements(configuration: configuration, current: [restored], history: [original])
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: values, now: start.addingTimeInterval(15 * 86_400)) == .expired)
        let revoked = VerifiedPurchase(productID: "trial", originalPurchaseDate: start, revoked: true, isVerified: true)
        let revokedValues = StoreKitProvider.entitlements(configuration: configuration, current: [], history: [revoked])
        #expect(revokedValues == [revoked])
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: revokedValues, now: start) == .expired)
    }

    @Test func historicalLifetimeAndUnverifiedRecordsCannotUnlock() {
        let lifetime = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: start, isVerified: true)
        let fake = VerifiedPurchase(productID: "trial", originalPurchaseDate: start, isVerified: false)
        let values = StoreKitProvider.entitlements(configuration: configuration, current: [fake], history: [lifetime, fake])
        #expect(values.isEmpty)
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: values, now: start) == .notStarted)
        let active = StoreKitProvider.entitlements(configuration: configuration, current: [lifetime], history: [])
        #expect(AccessPolicy.evaluate(configuration: configuration, purchases: active, now: start) == .unlocked)
    }
}
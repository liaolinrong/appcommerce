import Foundation
import Testing
@testable import CommerceCore

actor MockPurchaseProvider: PurchaseProvider {
    var history: [VerifiedPurchase] = []
    var result: PurchaseResult = .cancelled
    var restoreFails = false
    var purchaseCalls = 0
    var restoreCalls = 0
    var priceCalls = 0
    var readCalls = 0
    var readsFail = false
    var holdsPurchase = false
    var heldPurchase: CheckedContinuation<PurchaseResult, Never>?
    var holdsNextRead = false
    var heldRead: CheckedContinuation<[VerifiedPurchase], Never>?
    let stream: AsyncStream<VerifiedPurchase>
    let continuation: AsyncStream<VerifiedPurchase>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func configure(history: [VerifiedPurchase] = [], result: PurchaseResult = .cancelled, restoreFails: Bool = false) {
        self.history = history
        self.result = result
        self.restoreFails = restoreFails
    }

    func purchases() async throws -> [VerifiedPurchase] {
        readCalls += 1
        if readsFail { throw CommerceError.providerFailure(message: "offline") }
        if holdsNextRead {
            holdsNextRead = false
            return await withCheckedContinuation { heldRead = $0 }
        }
        return history
    }

    func updates() async -> AsyncStream<VerifiedPurchase> { stream }

    func purchase(productID: String) async throws -> PurchaseResult {
        purchaseCalls += 1
        if holdsPurchase {
            return await withCheckedContinuation { heldPurchase = $0 }
        }
        if case .purchased(let purchase) = result, purchase.isVerified {
            history.append(purchase)
        }
        return result
    }

    func restore() async throws {
        restoreCalls += 1
        if restoreFails { throw CommerceError.providerFailure(message: "offline") }
    }

    func price(productID: String) async throws -> String? {
        priceCalls += 1
        return "$9.99"
    }

    func emit(_ purchase: VerifiedPurchase) {
        history = [purchase]
        continuation.yield(purchase)
    }

    func failReads() { readsFail = true }
    func holdNextRead() { holdsNextRead = true }
    func finishRead(_ purchases: [VerifiedPurchase]) {
        heldRead?.resume(returning: purchases)
        heldRead = nil
    }
    func holdPurchase() { holdsPurchase = true }
    func finishPurchase(_ result: PurchaseResult) {
        heldPurchase?.resume(returning: result)
        heldPurchase = nil
    }
}

struct FixedClock: CommerceClock {
    let date: Date
    func now() -> Date { date }
    func sleep(until deadline: Date) async throws {
        try await Task.sleep(for: .seconds(100_000))
    }
}

@MainActor
struct CommerceControllerTests {
    let configuration = CommerceConfiguration(trialProductID: "trial", lifetimeProductID: "lifetime")
    let now = Date(timeIntervalSince1970: 2_000_000)

    func controller(_ provider: MockPurchaseProvider) -> CommerceController {
        CommerceController(configuration: configuration, provider: provider, clock: FixedClock(date: now))
    }

    @Test func verifiedLifetimeUnlocks() async {
        let provider = MockPurchaseProvider()
        let purchase = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: true)
        await provider.configure(result: .purchased(purchase))
        let controller = controller(provider)
        #expect(controller.accessState == .checking)
        #expect(!controller.canEdit)
        await controller.purchaseLifetime()
        #expect(controller.accessState == .unlocked)
        #expect(controller.canEdit)
        #expect(controller.lastPurchaseResult == .purchased(purchase))
        #expect(!controller.isBusy)
        #expect(controller.error == nil)
    }

    @Test(arguments: [PurchaseResult.pending, .cancelled])
    func incompletePurchaseDoesNotGrant(result: PurchaseResult) async {
        let provider = MockPurchaseProvider()
        await provider.configure(result: result)
        let controller = controller(provider)
        await controller.startTrial()
        #expect(controller.accessState == .notStarted)
        #expect(!controller.canEdit)
        #expect(controller.lastPurchaseResult == result)
        #expect(controller.error == nil)
        #expect(!controller.isBusy)
    }

    @Test func unverifiedSuccessDoesNotGrant() async {
        let provider = MockPurchaseProvider()
        let purchase = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: false)
        await provider.configure(result: .purchased(purchase))
        let controller = controller(provider)
        await controller.purchaseLifetime()
        #expect(!controller.canEdit)
        #expect(controller.error == .verificationFailed)
        #expect(controller.lastPurchaseResult == nil)
    }

    @Test func revokedTrialCannotBeReclaimed() async {
        let provider = MockPurchaseProvider()
        let purchase = VerifiedPurchase(productID: "trial", originalPurchaseDate: now, revoked: true, isVerified: true)
        await provider.configure(history: [purchase])
        let controller = controller(provider)
        await controller.startTrial()
        #expect(controller.accessState == .expired)
        #expect(controller.error == .trialAlreadyUsed)
        #expect(await provider.purchaseCalls == 0)
    }

    @Test func restoreDoesNotRestartTrial() async {
        let provider = MockPurchaseProvider()
        let purchase = VerifiedPurchase(productID: "trial", originalPurchaseDate: now.addingTimeInterval(-15 * 86_400), isVerified: true)
        await provider.configure(history: [purchase])
        let controller = controller(provider)
        await controller.restorePurchases()
        #expect(controller.accessState == .expired)
        #expect(controller.lastRestoreSucceeded == true)
        #expect(await provider.restoreCalls == 1)
        await controller.startTrial()
        #expect(controller.error == .trialAlreadyUsed)
        #expect(await provider.purchaseCalls == 0)
    }

    @Test func failedRestoreDoesNotGrant() async {
        let provider = MockPurchaseProvider()
        let purchase = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: true)
        await provider.configure(history: [purchase], restoreFails: true)
        let controller = controller(provider)
        await controller.restorePurchases()
        #expect(!controller.canEdit)
        #expect(controller.lastRestoreSucceeded == false)
        #expect(controller.error == .providerFailure(message: "offline"))
        #expect(!controller.isBusy)
    }

    @Test func startupIsIdempotentAndDoesNotQueryProductsOrSync() async {
        let provider = MockPurchaseProvider()
        let purchase = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: true)
        await provider.configure(history: [purchase])
        let controller = controller(provider)
        controller.start()
        controller.start()
        for _ in 0..<1_000 {
            if controller.accessState == .unlocked { break }
            await Task.yield()
        }
        #expect(controller.accessState == .unlocked)
        #expect(await provider.readCalls == 1)
        #expect(await provider.priceCalls == 0)
        #expect(await provider.restoreCalls == 0)
        let revoked = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, revoked: true, isVerified: true)
        await provider.emit(revoked)
        for _ in 0..<1_000 {
            if controller.accessState == .notStarted { break }
            await Task.yield()
        }
        #expect(!controller.canEdit)
        controller.stop()
    }

    @Test func verifiedRevocationUpdateWorksWithoutAnotherRead() async {
        let provider = MockPurchaseProvider()
        let purchase = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: true)
        await provider.configure(history: [purchase])
        let controller = controller(provider)
        controller.start()
        for _ in 0..<1_000 {
            if controller.canEdit { break }
            await Task.yield()
        }
        #expect(controller.canEdit)
        await provider.failReads()
        await provider.emit(VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, revoked: true, isVerified: true))
        for _ in 0..<1_000 {
            if !controller.canEdit { break }
            await Task.yield()
        }
        #expect(!controller.canEdit)
        #expect(await provider.readCalls == 1)
        controller.stop()
    }

    @Test func unverifiedUpdateAndEntitlementCannotGrant() async {
        let provider = MockPurchaseProvider()
        let fake = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: false)
        await provider.configure(history: [fake])
        let controller = controller(provider)
        await controller.refresh()
        #expect(controller.accessState == .notStarted)
        controller.start()
        for _ in 0..<1_000 {
            if await provider.readCalls == 2 { break }
            await Task.yield()
        }
        await provider.emit(fake)
        await Task.yield()
        #expect(!controller.canEdit)
        #expect(await provider.readCalls == 2)
        controller.stop()
    }

    @Test func busyPreventsOverlappingPurchaseAndRestore() async {
        let provider = MockPurchaseProvider()
        await provider.holdPurchase()
        let controller = controller(provider)
        let purchaseTask = Task { await controller.purchaseLifetime() }
        for _ in 0..<1_000 {
            if await provider.heldPurchase != nil { break }
            await Task.yield()
        }
        #expect(controller.isBusy)
        await controller.startTrial()
        await controller.restorePurchases()
        #expect(await provider.purchaseCalls == 1)
        #expect(await provider.restoreCalls == 0)
        await provider.finishPurchase(.pending)
        await purchaseTask.value
        #expect(!controller.isBusy)
        #expect(controller.lastPurchaseResult == .pending)
        #expect(!controller.canEdit)
    }

    @Test func trialPurchaseUsesOriginalDateAndPriceIsLazy() async throws {
        let provider = MockPurchaseProvider()
        let start = now.addingTimeInterval(-86_400)
        let purchase = VerifiedPurchase(productID: "trial", originalPurchaseDate: start, isVerified: true)
        await provider.configure(result: .purchased(purchase))
        let controller = controller(provider)
        await controller.startTrial()
        #expect(controller.accessState == .trial(expiresAt: start.addingTimeInterval(15 * 86_400)))
        #expect(await provider.priceCalls == 0)
        let price = try await controller.price(for: "lifetime")
        #expect(price == "$9.99")
        #expect(await provider.priceCalls == 1)
        controller.stop()
    }

    @Test func unrelatedPurchaseResultDoesNotGrant() async {
        let provider = MockPurchaseProvider()
        await provider.configure(result: .purchased(VerifiedPurchase(productID: "other", originalPurchaseDate: now, isVerified: true)))
        let controller = controller(provider)
        await controller.purchaseLifetime()
        #expect(controller.error == .unexpectedProduct)
        #expect(!controller.canEdit)
    }

    @Test func startupUpdateCannotDiscardEarlierTrialHistory() async {
        let provider = MockPurchaseProvider()
        await provider.holdNextRead()
        let controller = controller(provider)
        controller.start()
        for _ in 0..<1_000 {
            if await provider.heldRead != nil { break }
            await Task.yield()
        }
        let recent = VerifiedPurchase(productID: "trial", originalPurchaseDate: now, isVerified: true)
        await provider.emit(recent)
        for _ in 0..<100 { await Task.yield() }
        #expect(controller.accessState == .checking)
        #expect(!controller.canEdit)
        let original = VerifiedPurchase(productID: "trial", originalPurchaseDate: now.addingTimeInterval(-15 * 86_400), isVerified: true)
        await provider.finishRead([original])
        for _ in 0..<1_000 {
            if controller.accessState == .expired { break }
            await Task.yield()
        }
        #expect(controller.accessState == .expired)
        await controller.refresh()
        #expect(controller.accessState == .expired)
        await controller.startTrial()
        #expect(controller.error == .trialAlreadyUsed)
        #expect(await provider.purchaseCalls == 0)
        controller.stop()
    }

    @Test func staleRefreshCannotUndoVerifiedLifetimeRevocation() async {
        let provider = MockPurchaseProvider()
        let active = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: true)
        await provider.configure(history: [active])
        let controller = controller(provider)
        controller.start()
        for _ in 0..<1_000 {
            if controller.canEdit { break }
            await Task.yield()
        }
        await provider.holdNextRead()
        let refreshTask = Task { await controller.refresh() }
        for _ in 0..<1_000 {
            if await provider.heldRead != nil { break }
            await Task.yield()
        }
        let revoked = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, revoked: true, isVerified: true)
        await provider.emit(revoked)
        for _ in 0..<1_000 {
            if !controller.canEdit { break }
            await Task.yield()
        }
        #expect(!controller.canEdit)
        await provider.finishRead([active])
        await refreshTask.value
        #expect(!controller.canEdit)
        controller.stop()
    }

    @Test func successfulRestoreLoadsVerifiedLifetime() async {
        let provider = MockPurchaseProvider()
        let purchase = VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: true)
        await provider.configure(history: [purchase])
        let controller = controller(provider)
        await controller.restorePurchases()
        #expect(controller.accessState == .unlocked)
        #expect(controller.canEdit)
        #expect(controller.lastRestoreSucceeded == true)
        #expect(controller.error == nil)
    }

    @Test func failedRefreshStartsClosedAndPreservesAlreadyVerifiedAccess() async {
        let provider = MockPurchaseProvider()
        await provider.failReads()
        let controller = controller(provider)
        await controller.refresh()
        #expect(controller.accessState == .checking)
        #expect(!controller.canEdit)
        #expect(controller.error != nil)

        let availableProvider = MockPurchaseProvider()
        await availableProvider.configure(history: [VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: true)])
        let available = self.controller(availableProvider)
        await available.refresh()
        await availableProvider.failReads()
        await available.refresh()
        #expect(available.canEdit)
        #expect(available.error != nil)
    }

    @Test func emptyCurrentEntitlementsRemoveLifetimeAccess() async {
        let provider = MockPurchaseProvider()
        await provider.configure(history: [VerifiedPurchase(productID: "lifetime", originalPurchaseDate: now, isVerified: true)])
        let controller = controller(provider)
        await controller.refresh()
        #expect(controller.canEdit)
        await provider.configure()
        await controller.refresh()
        #expect(controller.accessState == .notStarted)
        #expect(!controller.canEdit)
    }
}
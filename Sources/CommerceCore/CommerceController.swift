import Foundation
import Observation

@MainActor
@Observable
public final class CommerceController {
    public let configuration: CommerceConfiguration
    public private(set) var accessState: AccessState = .checking
    public private(set) var isBusy = false
    public private(set) var error: CommerceError?
    public private(set) var lastPurchaseResult: PurchaseResult?
    public private(set) var lastRestoreSucceeded: Bool?

    public var canEdit: Bool {
        if case .trial(let expiration) = accessState {
            return clock.now() < expiration
        }
        return accessState.canEdit
    }

    @ObservationIgnored private let provider: any PurchaseProvider
    @ObservationIgnored private let clock: any CommerceClock
    @ObservationIgnored private var knownPurchases: [VerifiedPurchase] = []
    @ObservationIgnored private var trialHistory: [VerifiedPurchase] = []
    @ObservationIgnored private var hasLoadedPurchases = false
    @ObservationIgnored private var refreshVersion = 0
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var expirationTask: Task<Void, Never>?

    public convenience init(configuration: CommerceConfiguration, provider: any PurchaseProvider) {
        self.init(configuration: configuration, provider: provider, clock: SystemCommerceClock())
    }

    public init(
        configuration: CommerceConfiguration,
        provider: any PurchaseProvider,
        clock: any CommerceClock
    ) {
        self.configuration = configuration
        self.provider = provider
        self.clock = clock
    }

    deinit {
        updatesTask?.cancel()
        expirationTask?.cancel()
    }

    public func start() {
        guard updatesTask == nil else { return }
        let provider = provider
        updatesTask = Task { [weak self] in
            let stream = await provider.updates()
            guard !Task.isCancelled else { return }
            await self?.refresh()
            for await purchase in stream {
                guard !Task.isCancelled else { return }
                guard purchase.isVerified else { continue }
                self?.receive(purchase)
            }
        }
    }

    public func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        expirationTask?.cancel()
        expirationTask = nil
    }

    public func refresh() async {
        do {
            try await reload()
            error = nil
        } catch {
            record(error)
            updateAccess()
        }
    }

    public func startTrial() async {
        await buy(productID: configuration.trialProductID, isTrial: true)
    }

    public func purchaseLifetime() async {
        await buy(productID: configuration.lifetimeProductID, isTrial: false)
    }

    public func restorePurchases() async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        lastRestoreSucceeded = nil
        defer { isBusy = false }
        do {
            try await provider.restore()
            try await reload()
            lastRestoreSucceeded = true
        } catch {
            lastRestoreSucceeded = false
            record(error)
            updateAccess()
        }
    }

    public func price(for productID: String) async throws -> String? {
        try await provider.price(productID: productID)
    }

    private func buy(productID: String, isTrial: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        lastPurchaseResult = nil
        defer { isBusy = false }
        do {
            try await reload()
            if accessState == .unlocked { throw CommerceError.alreadyUnlocked }
            if isTrial && knownPurchases.contains(where: {
                $0.isVerified && $0.productID == configuration.trialProductID
            }) {
                throw CommerceError.trialAlreadyUsed
            }
            let result = try await provider.purchase(productID: productID)
            if case .purchased(let purchase) = result {
                guard purchase.isVerified else { throw CommerceError.verificationFailed }
                guard purchase.productID == productID else { throw CommerceError.unexpectedProduct }
                receive(purchase)
            }
            lastPurchaseResult = result
        } catch {
            record(error)
            updateAccess()
        }
    }

    private func reload() async throws {
        refreshVersion += 1
        let version = refreshVersion
        let purchases = try await provider.purchases()
        try Task.checkCancellation()
        let verified = purchases.filter(\.isVerified)
        rememberTrials(verified)
        hasLoadedPurchases = true
        if version == refreshVersion {
            knownPurchases = verified.filter { $0.productID != configuration.trialProductID } + trialHistory
        } else {
            knownPurchases = knownPurchases.filter { $0.productID != configuration.trialProductID } + trialHistory
        }
        updateAccess()
    }

    private func receive(_ purchase: VerifiedPurchase) {
        guard purchase.productID == configuration.trialProductID ||
              purchase.productID == configuration.lifetimeProductID else { return }
        refreshVersion += 1
        if purchase.productID == configuration.lifetimeProductID {
            knownPurchases.removeAll { $0.productID == configuration.lifetimeProductID }
            knownPurchases.append(purchase)
        } else {
            rememberTrials([purchase])
            knownPurchases = knownPurchases.filter { $0.productID != configuration.trialProductID } + trialHistory
        }
        updateAccess()
    }

    private func rememberTrials(_ purchases: [VerifiedPurchase]) {
        for purchase in purchases where purchase.productID == configuration.trialProductID && purchase.isVerified {
            if !trialHistory.contains(purchase) { trialHistory.append(purchase) }
        }
    }

    private func updateAccess() {
        guard hasLoadedPurchases || knownPurchases.contains(where: {
            $0.productID == configuration.lifetimeProductID && $0.isVerified && !$0.revoked
        }) else {
            accessState = .checking
            return
        }
        accessState = AccessPolicy.evaluate(
            configuration: configuration,
            purchases: knownPurchases,
            now: clock.now()
        )
        expirationTask?.cancel()
        expirationTask = nil
        guard case .trial(let expiration) = accessState else { return }
        let clock = clock
        expirationTask = Task { [weak self] in
            do {
                try await clock.sleep(until: expiration)
                try Task.checkCancellation()
                self?.updateAccess()
            } catch {}
        }
    }

    private func record(_ failure: any Error) {
        error = (failure as? CommerceError) ?? .providerFailure(message: String(describing: failure))
    }
}
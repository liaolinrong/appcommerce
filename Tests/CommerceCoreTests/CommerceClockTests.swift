import Foundation
import Testing
@testable import CommerceCore

final class ManualClock: CommerceClock, @unchecked Sendable {
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var date: Date
    private var sleepers: [UUID: Sleeper] = [:]

    init(date: Date) { self.date = date }

    func now() -> Date { lock.withLock { date } }
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Date) async throws {
        let identifier = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.withLock {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if deadline <= date {
                        continuation.resume()
                    } else {
                        sleepers[identifier] = Sleeper(deadline: deadline, continuation: continuation)
                    }
                }
            }
        } onCancel: {
            let sleeper = self.lock.withLock { self.sleepers.removeValue(forKey: identifier) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(to date: Date) {
        let ready = lock.withLock {
            self.date = date
            let ready = sleepers.filter { $0.value.deadline <= date }
            for identifier in ready.keys { sleepers.removeValue(forKey: identifier) }
            return Array(ready.values)
        }
        for sleeper in ready { sleeper.continuation.resume() }
    }
}

@MainActor
struct CommerceClockTests {
    @Test func controllerExpiresAutomaticallyAtExactDeadline() async {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let expiration = start.addingTimeInterval(15 * 86_400)
        let clock = ManualClock(date: expiration.addingTimeInterval(-1))
        let provider = MockPurchaseProvider()
        await provider.configure(history: [VerifiedPurchase(productID: "trial", originalPurchaseDate: start, isVerified: true)])
        let controller = CommerceController(
            configuration: CommerceConfiguration(trialProductID: "trial", lifetimeProductID: "lifetime"),
            provider: provider,
            clock: clock
        )
        await controller.refresh()
        #expect(controller.canEdit)
        for _ in 0..<1_000 {
            if clock.sleeperCount == 1 { break }
            await Task.yield()
        }
        #expect(clock.sleeperCount == 1)
        clock.advance(to: expiration)
        #expect(!controller.canEdit)
        for _ in 0..<1_000 {
            if controller.accessState == .expired { break }
            await Task.yield()
        }
        #expect(controller.accessState == .expired)
        controller.stop()
    }
}
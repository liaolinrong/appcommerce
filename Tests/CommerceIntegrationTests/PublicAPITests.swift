import CommerceCore
import CommerceStoreKit
import CommerceUI
import SwiftUI
import Testing

@MainActor
struct PublicAPITests {
    @Test func allProductsComposeWithoutStoreRequests() {
        let configuration = CommerceConfiguration(
            trialProductID: "com.example.app.trial",
            lifetimeProductID: "com.example.app.lifetime"
        )
        let provider = StoreKitProvider(configuration: configuration)
        let controller = CommerceController(configuration: configuration, provider: provider)
        #expect(controller.accessState == .checking)
        #expect(!controller.canEdit)
        #expect(!controller.isBusy)
        #expect(controller.error == nil)
        #expect(controller.lastPurchaseResult == nil)
        #expect(controller.lastRestoreSucceeded == nil)
        _ = CommerceStatusView(controller: controller, language: .english)
        _ = CommerceStatusView(controller: controller, language: .simplifiedChinese)
        _ = CommerceStateView(controller: controller) { _, canEdit, isBusy, _ in
            Image(systemName: canEdit ? "lock.open" : "lock")
                .opacity(isBusy ? 0.5 : 1)
        }
    }
}
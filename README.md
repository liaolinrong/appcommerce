# AppCommerce

Independent Swift Package, Swift tools 6.0, Swift 6 language mode, macOS 14+.
No external dependencies, Markdown/editor functionality, app-specific persistence,
or dependency on DawnMark or any other host app.

独立 Swift Package，使用 Swift tools 6.0、Swift 6 语言模式，支持 macOS 14+。
无外部依赖，不依赖 DawnMark 或任何宿主应用，不包含 Markdown、编辑器或应用专用持久化逻辑。

## Products

- `CommerceCore`: Sendable values, pure access policy, injectable provider/clock,
  and a `@MainActor @Observable` controller.
- `CommerceStoreKit`: StoreKit 2 implementation with verified transactions only.
- `CommerceUI`: optional SwiftUI state/status views. The app owns its layout,
  purchase buttons, paywall, and editing restrictions.

## App Store Connect Setup

Create two **non-consumable** in-app purchases for your own app and use their
actual App Store Connect product identifiers, not the example identifiers below:

1. A free, price-tier-zero non-consumable named **15-day Trial**.
2. A paid non-consumable for lifetime access.

Configure availability, pricing, localized metadata, agreements, and the app's
In-App Purchase capability. Confirm the trial configuration complies with current
App Review requirements. Before trial confirmation, the host app must disclose
the 15-day duration, what becomes restricted when it ends, and the full-unlock
price. This is not a subscription introductory offer. The non-consumable itself
does not expire in StoreKit: this package computes the trial deadline locally.
Neither product is consumed to enable repeated trials. Wrong/missing identifiers
or non-non-consumable product types fail closed.

```swift
import CommerceCore
import CommerceStoreKit
import CommerceUI

@MainActor
func makeCommerce() -> CommerceController {
    let configuration = CommerceConfiguration(
        trialProductID: "com.example.app.trial",
        lifetimeProductID: "com.example.app.lifetime"
    )
    let provider = StoreKitProvider(configuration: configuration)
    let controller = CommerceController(configuration: configuration, provider: provider)
    controller.start()
    return controller
}
```

Keep the controller alive in app-owned state. Gate **all mutation paths**, not just
buttons, with `controller.canEdit`. Call `await controller.refresh()` when the app
returns to the foreground or the App Store account changes. For an account change,
stop and recreate the controller: verified trial history is deliberately retained
for the lifetime of each controller and is not keyed by account.

## Public API

### CommerceCore

`CommerceConfiguration: Sendable, Equatable`

- `init(trialProductID: String, lifetimeProductID: String, trialDuration: TimeInterval = 15 * 86_400)`
- Immutable `trialProductID`, `lifetimeProductID`, `trialDuration`.
- IDs must be nonempty and distinct; duration must be finite and positive.

`VerifiedPurchase: Sendable, Equatable`

- `init(productID: String, originalPurchaseDate: Date, revoked: Bool = false, isVerified: Bool)`
- Immutable properties with the same names. `isVerified` is an explicit defensive
  flag, **not** cryptographic verification. Custom providers are a trust boundary:
  they must only mark authenticated purchases verified. Never derive it from a
  UserDefaults Boolean or another local unlock flag.

`AccessState: Sendable, Equatable`

- `.checking`, `.notStarted`, `.trial(expiresAt: Date)`, `.unlocked`, `.expired`.
- `canEdit: Bool` describes the state's meaning. Use **controller.canEdit** for
  real editing checks because it also checks the clock against the deadline.

`AccessPolicy.evaluate(configuration: CommerceConfiguration, purchases: [VerifiedPurchase], now: Date) -> AccessState`

- Ignores unverified/unrelated records. An active verified lifetime purchase wins.
- Trial starts at the earliest verified `originalPurchaseDate`, not the restore
  time. Access ends at exactly `start + 1_296_000` seconds by default.
- Any verified trial revocation makes that trial expired and prevents reclaiming.

`PurchaseResult: Sendable, Equatable`

- `.purchased(VerifiedPurchase)`, `.pending`, `.cancelled`.
- Pending/cancellation do not grant access and are not errors. Pending approval
  can subsequently arrive through verified updates.

`CommerceError: Error, Sendable, Equatable`

- `.verificationFailed`, `.unexpectedProduct`, `.productUnavailable`,
  `.trialAlreadyUsed`, `.alreadyUnlocked`, `.providerFailure(message: String)`.
- Provider failure messages are diagnostics. Do not display raw messages as
  localized UI; the optional status view maps them to localized generic text.

`PurchaseProvider: Sendable`

```swift
func purchases() async throws -> [VerifiedPurchase]
func updates() async -> AsyncStream<VerifiedPurchase>
func purchase(productID: String) async throws -> PurchaseResult
func restore() async throws
func price(productID: String) async throws -> String?
```

`purchases()` must return current lifetime entitlements **and all verified trial
history**, including revoked trials and the earliest original purchase date.
`updates()` should yield only verified records, including revocations; Core also
checks the flag defensively. A successful purchase must already be verified and
finished by the provider. `price` has a default implementation returning `nil`.
Mock providers and manual clocks are demonstrated in the test targets.

`CommerceClock: Sendable`

```swift
func now() -> Date
func sleep(until deadline: Date) async throws
```

Sleep must wait until the deadline and support cancellation; a mock must advance
its date before waking sleepers. `SystemCommerceClock.init()` uses the system
date and cancellable task sleep. No product query or sync is involved.

`@MainActor @Observable public final class CommerceController`

```swift
public init(configuration: CommerceConfiguration, provider: any PurchaseProvider)
public init(configuration: CommerceConfiguration, provider: any PurchaseProvider, clock: any CommerceClock)
public func start()
public func stop()
public func refresh() async
public func startTrial() async
public func purchaseLifetime() async
public func restorePurchases() async
public func price(for productID: String) async throws -> String?
```

Read-only public state: `configuration`, `accessState: AccessState`, `canEdit: Bool`,
`isBusy: Bool`, `error: CommerceError?`, `lastPurchaseResult: PurchaseResult?`,
`lastRestoreSucceeded: Bool?`.

- **`start()` is synchronous**, idempotent, and launches a task. It subscribes to
  updates before reading existing entitlements. Construction itself does no work.
- Startup/refresh never query `Product.products` or call `AppStore.sync`.
  StoreKit may perform its own OS-managed background activity.
- Only `restorePurchases()` invokes explicit sync. It then reads verified rights;
  restore alone is not a purchase or authorization.
- Purchase/restore operations use `isBusy` to reject overlapping commands. They
  report failure in `error` instead of throwing. `refresh` is background work and
  does not set `isBusy`. `price` throws to its caller and does not change that state.
- `lastPurchaseResult` is reset on a new purchase attempt; failed attempts leave
  it `nil`. Restore uses the separate optional `lastRestoreSucceeded` flag.
- Before any successful snapshot, trial state remains `.checking` and read errors
  fail closed. An independently verified lifetime update can unlock immediately.
- Verified updates apply directly, including revocations, without relying on a
  subsequent read. Older in-flight snapshots cannot overwrite newer updates.
  Verified trial history is merged even from older snapshots, so updates/restore
  do not reset a trial. No unlock flags are stored or read from UserDefaults.
- Trial expiration is scheduled with the injected clock. `canEdit` also checks
  time synchronously, covering a suspended app before the timer resumes.
- Read/restore failure does not create new rights or discard previously verified
  access. Expired trials still expire. Successful reads can remove lifetime rights.
- `stop()` cancels listening and the timer; deinitialization also cancels them.
  Call `start()` again to resume. Preserve the controller while listening is needed.

### CommerceStoreKit

`public actor StoreKitProvider: PurchaseProvider`

- `init(configuration: CommerceConfiguration)` and immutable `configuration`.
- Implements all five `PurchaseProvider` methods.
- Uses `Transaction.currentEntitlements` for current rights and `Transaction.all`
  for complete trial history. Old lifetime history alone never grants access.
- Unverified transactions and non-non-consumable transactions are ignored.
- `.success(.verified)` purchases and verified configured updates are finished.
  Unverified purchases throw; pending and user cancellation remain distinct results.
- `AppStore.sync()` exists only in `restore()`. Product fetching is lazy, only on
  `purchase(productID:)` or `price(productID:)`, and prices come from `displayPrice`.

### CommerceUI

- `CommerceStateView<Content: View>.init(controller: CommerceController, content:)`
  accepts a `@ViewBuilder (AccessState, Bool, Bool, CommerceError?) -> Content`.
  This unstyled view has no built-in copy. It observes controller changes.
- `CommerceStatusView.init(controller: CommerceController, language: CommerceLanguage)`
  shows localized status, a busy indicator, and generic localized errors.
- `CommerceLanguage` supports the 15 languages listed below. Language selection
  is explicit; the package does not inspect a host app's language configuration.
  All 12 `CommerceTextKey` values have native translations in every language.
  Resources are read from the exact selected language table, never silently from
  English; missing tables/keys are packaging errors. Dates use the selected locale.

#### Localization / 本地化

| Language / 语言 | Resource Identifier / 资源标识 | CommerceLanguage Case / 枚举成员 |
| --- | --- | --- |
| English / 英语 | `en` | `.english` |
| Simplified Chinese / 简体中文 | `zh-Hans` | `.simplifiedChinese` |
| Traditional Chinese / 繁体中文 | `zh-Hant` | `.traditionalChinese` |
| Japanese / 日语 | `ja` | `.japanese` |
| Korean / 韩语 | `ko` | `.korean` |
| French / 法语 | `fr` | `.french` |
| German / 德语 | `de` | `.german` |
| Spanish / 西班牙语 | `es` | `.spanish` |
| Brazilian Portuguese / 巴西葡萄牙语 | `pt-BR` | `.brazilianPortuguese` |
| European Portuguese / 葡萄牙葡萄牙语 | `pt-PT` | `.europeanPortuguese` |
| Italian / 意大利语 | `it` | `.italian` |
| Dutch / 荷兰语 | `nl` | `.dutch` |
| Polish / 波兰语 | `pl` | `.polish` |
| Turkish / 土耳其语 | `tr` | `.turkish` |
| Indonesian / 印度尼西亚语 | `id` | `.indonesian` |

The package declares `defaultLocalization: "en"` for SwiftPM resource packaging,
not as a runtime fallback. Source `.lproj` directories retain the identifier case
shown above; the existing loader uses lowercase bundle paths, verified by SwiftPM
tests for all 15 languages. The 15 tables contain 180 values total; only `trial`
has a format placeholder, exactly one `%@` for the expiration date in each table.

语言由调用方显式选择，包不读取宿主应用的语言配置。全部 15 种语言各有 12 个键，
共 180 条原生文案；14 种非英语语言不会回退英文。缺少资源表或键视为打包错误。
`defaultLocalization: "en"` 用于 SwiftPM 打包，不是运行时兜底语言。
源码 `.lproj` 目录保留上表大小写，现有加载器使用小写 bundle 路径，已逐语言测试验证。
日期采用选定语言的 locale；仅 `trial` 含占位符，每种语言恰好一个 `%@`。

```swift
CommerceStatusView(controller: commerce, language: .simplifiedChinese)

CommerceStateView(controller: commerce) { state, canEdit, isBusy, error in
    // Provide your own app-localized UI and controls here.
    Image(systemName: canEdit ? "lock.open" : "lock")
        .opacity(isBusy ? 0.5 : 1)
}
```

## Validation And Limits

```sh
swift test
```

The tests cover exact 15-day boundaries, lifetime priority, revocation, earliest
history, mock provider/clock, automatic expiry, verified updates and stale-read
races, pending/cancelled outcomes, restore success/failure, non-resetting restore,
unverified rejection, lazy prices, startup without product lookup/sync, public API
composition, and the exact 15-language/12-key sets, completeness, absence of
English fallback text, placeholder safety, date interpolation, and status/error
mapping for every supported language.

本地化测试覆盖精确的 15 种语言与 12 个键、逐语言完整性、非英语文案不复用英文、
占位符安全、日期插值和状态／错误文案映射。测试只使用本包，无需 DawnMark。

These are deterministic unit/integration tests, **not real App Store purchase
tests**. Validate payment sheets, transaction finishing, refunds, pending approval,
offline cached entitlements, account changes, and restore with Xcode StoreKit
Testing and a Sandbox/TestFlight app before shipping. No live store authentication
or paid purchase is performed by `swift test`.

Offline device time cannot be made completely tamper-proof by a local library.
Clock changes, modified clients, missing local StoreKit history after reinstall,
and transactions not yet downloaded can affect decisions. Existing StoreKit
verified cached rights support offline access when available, but this package
does not promise offline discovery of missing history or new purchases. Use a
trusted server and App Store server verification/notifications for stronger
time/account enforcement. Custom providers must preserve verified trial history.
Full trial history is scanned on every explicit refresh; very large histories
may be slow. No receipt server, app-account binding, secure-time service,
subscription logic, or Markdown functionality is included.
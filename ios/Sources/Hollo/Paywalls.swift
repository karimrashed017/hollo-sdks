import StoreKit
import UIKit

// Paywall adapters (F-31): what tapping an offer card opens. StoreKit ships
// with iOS, so its adapter lives here. RevenueCat, Superwall and Adapty would
// make every app that uses Hollo download them, so their adapters are short
// `HolloPaywall { ref in … }` blocks in the docs instead.

/** How a paywall shown for an offer ended. Hollo tracks it as `offer_<result>`. */
public enum HolloPaywallResult: String, Sendable {
    case purchased, restored, declined, pending, failed
}

/** Shows the app's paywall for an offer's ref and reports how it ended. */
public struct HolloPaywall: Sendable {
    let show: @MainActor @Sendable (String) async -> HolloPaywallResult

    public init(_ show: @escaping @MainActor @Sendable (_ ref: String) async -> HolloPaywallResult) {
        self.show = show
    }

    /**
     * Presents a paywall's view controller over whatever is on screen, for
     * adapters. Returns false if nothing is on screen to present from.
     */
    @MainActor
    @discardableResult
    public static func present(_ controller: UIViewController) -> Bool {
        guard let top = Presenter.topViewController() else { return false }
        top.present(controller, animated: true)
        return true
    }

    /**
     * Buys the App Store product whose ID is the offer's ref, in Apple's
     * purchase sheet. `onPurchase` runs before the transaction is finished,
     * so unlock access there (or keep reading `Transaction.currentEntitlements`).
     * Pass `appAccountToken` (the UUID you pass to `identify`) so App Store
     * notifications reach the right profile in Hollo.
     */
    public static func storeKit(
        appAccountToken: UUID? = nil,
        onPurchase: (@MainActor @Sendable (Transaction) async -> Void)? = nil
    ) -> HolloPaywall {
        HolloPaywall { productID in
            do {
                guard let product = try await Product.products(for: [productID]).first else {
                    logger.error("Hollo: no App Store product with ID \(productID, privacy: .public)")
                    return .failed
                }
                var options: Set<Product.PurchaseOption> = []
                if let appAccountToken { options.insert(.appAccountToken(appAccountToken)) }
                switch try await product.purchase(options: options) {
                case .success(.verified(let transaction)):
                    await onPurchase?(transaction)
                    await transaction.finish()
                    return .purchased
                case .success(.unverified):
                    return .failed
                case .pending:
                    return .pending
                case .userCancelled:
                    return .declined
                @unknown default:
                    return .failed
                }
            } catch {
                return .failed
            }
        }
    }
}

extension Hollo {
    /**
     * Opens `paywall` when the user taps an offer card, after the chat closes,
     * and tracks how it ended (`offer_purchased`, `offer_declined`, …) so
     * automations can follow up. Replaces `onOffer`.
     */
    public static func usePaywall(_ paywall: HolloPaywall) {
        onOffer = { offer in
            Task { @MainActor in
                let result = await paywall.show(offer.id)
                track("offer_\(result.rawValue)")
            }
        }
    }
}

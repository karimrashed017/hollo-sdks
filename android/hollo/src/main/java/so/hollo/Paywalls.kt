package so.hollo

// Paywall adapters (F-31): what tapping an offer card opens. RevenueCat,
// Superwall and Adapty would make every app that uses Hollo download them, so
// their adapters are short HolloPaywall blocks in the docs instead.

/** How a paywall shown for an offer ended. Hollo tracks it as `offer_<result>`. */
enum class HolloPaywallResult(val value: String) {
    Purchased("purchased"),
    Restored("restored"),
    Declined("declined"),
    Pending("pending"),
    Failed("failed"),
}

/**
 * Shows the app's paywall for an offer's [ref] and calls [done] once with how
 * it ended. Called on the main thread after the chat closes.
 */
fun interface HolloPaywall {
    fun show(ref: String, done: (HolloPaywallResult) -> Unit)
}

/** Calls [paywall] for [ref]; an exception counts as Failed, and only the first result counts. */
internal fun runPaywall(paywall: HolloPaywall, ref: String, report: (HolloPaywallResult) -> Unit) {
    var reported = false
    val once = { result: HolloPaywallResult ->
        if (!reported) {
            reported = true
            report(result)
        }
    }
    try {
        paywall.show(ref, once)
    } catch (e: Exception) {
        once(HolloPaywallResult.Failed)
    }
}

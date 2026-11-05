// Paywall adapters (F-31): what tapping an offer card opens. RevenueCat,
// Superwall and Adapty would make every app that uses Hollo download them, so
// their adapters are short HolloPaywall functions in the docs instead.

/// How a paywall shown for an offer ended. Hollo tracks it as
/// `offer_<result>`.
enum HolloPaywallResult { purchased, restored, declined, pending, failed }

/// Shows the app's paywall for an offer's ref and reports how it ended.
typedef HolloPaywall = Future<HolloPaywallResult> Function(String ref);

/// Runs [paywall] for [ref]; an error counts as failed instead of crashing.
Future<HolloPaywallResult> runPaywall(HolloPaywall paywall, String ref) async {
  try {
    return await paywall(ref);
  } catch (_) {
    return HolloPaywallResult.failed;
  }
}

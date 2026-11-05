import 'package:flutter_test/flutter_test.dart';
import 'package:hollo/src/paywalls.dart';

void main() {
  test('passes the ref and the result through', () async {
    String? seen;
    final result = await runPaywall((ref) async {
      seen = ref;
      return HolloPaywallResult.purchased;
    }, 'winback');
    expect(seen, 'winback');
    expect(result, HolloPaywallResult.purchased);
  });

  test('turns an error into failed', () async {
    final result = await runPaywall((_) => throw StateError('no network'), 'x');
    expect(result, HolloPaywallResult.failed);
  });
}

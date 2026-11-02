import 'package:flutter_test/flutter_test.dart';
import 'package:hollo/src/cards.dart';
import 'package:hollo/src/links.dart';
import 'package:hollo/src/models.dart';

const both = {'appStoreId': '123456789', 'playStorePackage': 'com.example.app'};

void main() {
  group('reviewUrl', () {
    test('opens the App Store review sheet on iPhone', () {
      expect(
        reviewUrl('ios', both),
        'itms-apps://itunes.apple.com/app/id123456789?action=write-review',
      );
    });

    test('opens Google Play on Android', () {
      expect(reviewUrl('android', both), 'market://details?id=com.example.app');
    });

    test("falls back to a web link when the platform's store isn't set", () {
      expect(
        reviewUrl('android', {'appStoreId': '123456789'}),
        'https://apps.apple.com/app/id123456789?action=write-review',
      );
      expect(
        reviewUrl('web', {'playStorePackage': 'com.example.app'}),
        'https://play.google.com/store/apps/details?id=com.example.app',
      );
    });

    test('returns null with no store IDs', () {
      expect(reviewUrl('ios', {}), isNull);
      expect(reviewUrl('ios', {'appStoreId': null}), isNull);
    });
  });

  group('linkAction', () {
    test('opens a URL', () {
      final action = linkAction({'url': ' https://example.com '});
      expect(action, isA<UrlLinkAction>());
      expect((action as UrlLinkAction).url, 'https://example.com');
    });

    test('opens a screen with its value', () {
      final action = linkAction({'url': null, 'screen': 'order', 'value': '123'});
      expect(action, isA<ScreenLinkAction>());
      final screen = action as ScreenLinkAction;
      expect(screen.screen, 'order');
      expect(screen.value, '123');
    });

    test('opens a screen without a value', () {
      final action = linkAction({'screen': 'settings', 'value': null});
      expect((action as ScreenLinkAction).value, isNull);
    });

    test('refuses scripts and empty cards', () {
      expect(linkAction({'url': 'javascript:alert(1)'}), isNull);
      expect(linkAction({'url': 'DATA:text/html,hi'}), isNull);
      expect(linkAction({}), isNull);
    });
  });

  group('HolloCard', () {
    HolloMessage card(String kind, String body, Map<String, dynamic> payload) =>
        HolloMessage(
          id: '1',
          sender: 'team',
          kind: kind,
          body: body,
          createdAt: '2026-11-02T10:00:00Z',
          payload: payload,
        );

    test('a review request uses the message and button the server wrote', () {
      final result = HolloCard.fromMessage(
        card('review_request', 'Enjoying Driftwood?', {'cta': 'Bewerten'}),
      )!;
      expect(result.kind, HolloCardKind.review);
      expect(result.title, isEmpty);
      expect(result.text, 'Enjoying Driftwood?');
      expect(result.cta, 'Bewerten');
    });

    test('a review request has wording even when the server sent none', () {
      final result = HolloCard.fromMessage(card('review_request', '', {}))!;
      expect(result.text, 'Enjoying the app? A quick review helps us a lot.');
      expect(result.cta, 'Leave a review');
    });

    test('an offer shows its title, description and button', () {
      final result = HolloCard.fromMessage(
        card('offer', 'Half price', {
          'title': 'Half price for a year',
          'description': 'Today only',
          'cta': 'Get the offer',
          'ref': 'yearly_50',
        }),
      )!;
      expect(result.kind, HolloCardKind.offer);
      expect(result.title, 'Half price for a year');
      expect(result.text, 'Today only');
      expect(result.cta, 'Get the offer');
    });

    test('an offer without a button label says "See offer"', () {
      final result = HolloCard.fromMessage(
        card('offer', 'Half price', {'title': 'Half price', 'cta': null}),
      )!;
      expect(result.cta, 'See offer');
    });

    test('a link shows its body and label', () {
      final result = HolloCard.fromMessage(
        card('link', 'Track your order here', {'label': 'Track order'}),
      )!;
      expect(result.kind, HolloCardKind.link);
      expect(result.text, 'Track your order here');
      expect(result.cta, 'Track order');
      expect(HolloCard.fromMessage(card('link', 'x', {}))!.cta, 'Open');
    });

    test('a text message is not a card', () {
      expect(HolloCard.fromMessage(card('text', 'Hello', {})), isNull);
    });
  });
}

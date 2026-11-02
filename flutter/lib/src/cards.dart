import 'package:flutter/foundation.dart';

import 'json.dart';
import 'models.dart';

// What a card message shows: a review request (F-30), an offer (F-31) or a
// link (F-39). Kept out of the widgets so the wording rules are unit-tested.

enum HolloCardKind { review, offer, link }

@immutable
class HolloCard {
  const HolloCard({
    required this.kind,
    required this.title,
    required this.text,
    required this.cta,
  });

  /// The card for [message], or null when it's an ordinary text message.
  static HolloCard? fromMessage(HolloMessage message) {
    final payload = message.payload;
    String field(String key, String fallback) =>
        readString(payload[key]) ?? fallback;

    switch (message.kind) {
      case 'review_request':
        // The server writes the message and button in the user's language.
        return HolloCard(
          kind: HolloCardKind.review,
          title: '',
          text: message.body.isNotEmpty
              ? message.body
              : 'Enjoying the app? A quick review helps us a lot.',
          cta: field('cta', 'Leave a review'),
        );
      case 'link':
        return HolloCard(
          kind: HolloCardKind.link,
          title: '',
          text: message.body,
          cta: field('label', 'Open'),
        );
      case 'offer':
        return HolloCard(
          kind: HolloCardKind.offer,
          title: field('title', ''),
          text: field('description', ''),
          cta: field('cta', 'See offer'),
        );
      default:
        return null;
    }
  }

  final HolloCardKind kind;
  final String title;
  final String text;

  /// The button label.
  final String cta;
}

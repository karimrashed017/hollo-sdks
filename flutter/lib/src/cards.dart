import 'package:flutter/foundation.dart';

import 'json.dart';
import 'models.dart';

// What a card message shows: a review request (F-30), an offer (F-31), a
// link (F-39) or an action to confirm (F-42). Kept out of the widgets so the
// wording rules are unit-tested.

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

/// Where an action confirm card stands. [unavailable] is a card the server
/// refused because it was already answered elsewhere, or one in a state this
/// SDK doesn't know.
enum HolloConfirmState { pending, confirmed, cancelled, expired, unavailable }

/// An action confirm card (F-42): what the AI is about to change, waiting for
/// the user's Confirm or Cancel. Parsed like [HolloCard], so the rules are
/// unit-tested away from the widgets.
@immutable
class HolloConfirmation {
  const HolloConfirmation({
    required this.id,
    required this.title,
    required this.summary,
    required this.inputs,
    required this.risk,
    required this.state,
  });

  /// The card for [message], or null when it isn't an action confirm card or
  /// has no confirmation ID to answer (the chat then shows its body as text).
  /// [now] decides whether it has expired; tests pass a fixed time.
  static HolloConfirmation? fromMessage(HolloMessage message, {DateTime? now}) {
    if (message.kind != 'action_confirm') return null;
    final payload = message.payload;
    final id = readString(payload['confirmationId']);
    if (id == null) return null;

    final raw = payload['inputs'];
    final inputs = <({String label, String value})>[
      if (raw is List)
        for (final item in raw)
          if (item is Map && readString(item['label']) != null)
            (
              label: item['label'] as String,
              // Numbers and booleans still show; a missing value shows empty.
              value: item['value'] == null ? '' : '${item['value']}',
            ),
    ];

    final expires = DateTime.tryParse(readString(payload['expiresAt']) ?? '');
    final lapsed = expires != null && expires.isBefore(now ?? DateTime.now());
    final state = switch (payload['status']) {
      'confirmed' || 'used' => HolloConfirmState.confirmed,
      'cancelled' => HolloConfirmState.cancelled,
      'expired' => HolloConfirmState.expired,
      // A missing status counts as waiting, until the card's time runs out.
      'pending' || null =>
        lapsed ? HolloConfirmState.expired : HolloConfirmState.pending,
      _ => HolloConfirmState.unavailable,
    };

    return HolloConfirmation(
      id: id,
      title: readString(payload['title']) ?? 'Confirm',
      summary: readString(payload['summary']) ?? message.body,
      inputs: List.unmodifiable(inputs),
      risk: switch (payload['risk']) {
        'medium' => 'medium',
        'high' => 'high',
        _ => 'low',
      },
      state: state,
    );
  }

  /// The ID POST /confirmations answers.
  final String id;
  final String title;

  /// One line on what will change.
  final String summary;

  /// What the action will use, shown as "label: value".
  final List<({String label, String value})> inputs;

  /// `low`, `medium` or `high`.
  final String risk;
  final HolloConfirmState state;
}

/// The line a decided card shows in place of its buttons.
String holloConfirmStateLabel(HolloConfirmState state) => switch (state) {
      HolloConfirmState.pending => '',
      HolloConfirmState.confirmed => 'Confirmed',
      HolloConfirmState.cancelled => 'Cancelled',
      HolloConfirmState.expired => 'Expired',
      HolloConfirmState.unavailable => 'No longer available',
    };

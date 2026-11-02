import 'package:flutter/foundation.dart';

import 'json.dart';

/// One message in the user's conversation.
@immutable
class HolloMessage {
  const HolloMessage({
    required this.id,
    required this.sender,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.payload = const <String, dynamic>{},
  });

  factory HolloMessage.fromJson(Map<String, dynamic> json) => HolloMessage(
        id: readString(json['id']) ?? '',
        sender: readString(json['sender']) ?? 'system',
        kind: readString(json['kind']) ?? 'text',
        body: readString(json['body']) ?? '',
        createdAt: readString(json['created_at']) ?? '',
        payload: readMap(json['payload']),
      );

  final String id;

  /// `end_user`, `team`, `ai` or `system`.
  final String sender;

  /// `text`, `review_request`, `offer` or `link`.
  final String kind;

  final String body;

  /// Card details for review_request, offer and link messages.
  final Map<String, dynamic> payload;

  /// Kept exactly as the server sent it, because polling sends it back as
  /// `after` and reformatting could drop the microseconds.
  final String createdAt;

  /// Sent by the user on this device (or another of their devices).
  bool get fromUser => sender == 'end_user';

  @override
  String toString() => 'HolloMessage($id, $sender, $kind)';
}

/// An offer card the user tapped. [ref] is the ID you set in the dashboard.
@immutable
class HolloOffer {
  const HolloOffer({required this.ref, required this.title});

  final String ref;
  final String title;

  @override
  String toString() => 'HolloOffer($ref)';
}

/// A link card that opens one of your app's screens. [screen] is the name you
/// gave it in the dashboard, [value] its optional value (an order number, say).
@immutable
class HolloLink {
  const HolloLink({required this.screen, this.value});

  final String screen;
  final String? value;

  @override
  String toString() => 'HolloLink($screen, $value)';
}

/// Who answers, set on the app's page in the dashboard. Every field is
/// optional.
@immutable
class HolloProfile {
  const HolloProfile({this.name, this.role, this.photo, this.welcome});

  factory HolloProfile.fromJson(Map<String, dynamic> json) {
    final photo = readString(json['photo']);
    return HolloProfile(
      name: readString(json['name']),
      role: readString(json['role']),
      // The server only saves https uploads, but check on the way in too.
      photo: photo != null && photo.startsWith('https://') ? photo : null,
      welcome: readString(json['welcome']),
    );
  }

  final String? name;
  final String? role;
  final String? photo;
  final String? welcome;
}

/// When the chat asks to turn on notifications, from the dashboard.
enum HolloPermissionCard { off, replies, repliesOffers }

/// Push options from the dashboard.
@immutable
class HolloPushSettings {
  const HolloPushSettings({
    this.permissionCard = HolloPermissionCard.off,
    this.notifyLine = true,
  });

  factory HolloPushSettings.fromJson(Map<String, dynamic> json) =>
      HolloPushSettings(
        permissionCard: switch (json['permissionCard']) {
          'replies' => HolloPermissionCard.replies,
          'replies_offers' => HolloPermissionCard.repliesOffers,
          _ => HolloPermissionCard.off,
        },
        notifyLine: json['notifyLine'] != false,
      );

  final HolloPermissionCard permissionCard;

  /// Show "We'll send you a notification" under the user's latest message.
  final bool notifyLine;
}

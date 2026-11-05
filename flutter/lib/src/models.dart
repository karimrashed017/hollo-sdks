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
    this.photos = const <String>[],
  });

  factory HolloMessage.fromJson(Map<String, dynamic> json) => HolloMessage(
        id: readString(json['id']) ?? '',
        sender: readString(json['sender']) ?? 'system',
        kind: readString(json['kind']) ?? 'text',
        body: readString(json['body']) ?? '',
        createdAt: readString(json['created_at']) ?? '',
        payload: readMap(json['payload']),
        photos: _readPhotos(json['photos']),
      );

  final String id;

  /// `end_user`, `team`, `ai` or `system`.
  final String sender;

  /// `text`, `image`, `review_request`, `offer`, `link` or `action_confirm`.
  final String kind;

  /// The text, or an image message's caption (often empty).
  final String body;

  /// Card details for review_request, offer, link and action_confirm
  /// messages.
  final Map<String, dynamic> payload;

  /// An image message's photos as signed URLs, in order. They expire after
  /// a day; the next start fetches fresh ones. Older servers send none.
  final List<String> photos;

  /// Kept exactly as the server sent it, because polling sends it back as
  /// `after` and reformatting could drop the microseconds.
  final String createdAt;

  /// Sent by the user on this device (or another of their devices).
  bool get fromUser => sender == 'end_user';

  @override
  String toString() => 'HolloMessage($id, $sender, $kind)';
}

/// Web URLs only, so nothing else ever reaches Image.network. Plain http is
/// kept for a local Supabase in development.
List<String> _readPhotos(Object? value) => value is List
    ? List<String>.unmodifiable(
        value.whereType<String>().where(
              (url) => url.startsWith('https://') || url.startsWith('http://'),
            ),
      )
    : const <String>[];

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

/// A dashboard colour for the light look, the dark look or both, as
/// 0xFFRRGGBB.
@immutable
class HolloRemoteColor {
  const HolloRemoteColor({this.light, this.dark});

  final int? light;
  final int? dark;

  /// The half for this look, or null so the app's own colour stays.
  int? pick({required bool dark}) => dark ? this.dark : light;

  @override
  bool operator ==(Object other) =>
      other is HolloRemoteColor && other.light == light && other.dark == dark;

  @override
  int get hashCode => Object.hash(light, dark);
}

final RegExp _hexColor = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// "#RRGGBB" as an opaque colour; anything else is null.
int? readHexColor(Object? value) =>
    value is String && _hexColor.hasMatch(value)
        ? 0xFF000000 | int.parse(value.substring(1), radix: 16)
        : null;

/// Chat colours and title set in the dashboard, applied over the app's
/// HolloTheme so the look changes without an app release. Every field is
/// optional, and anything malformed is dropped.
@immutable
class HolloRemoteTheme {
  const HolloRemoteTheme({
    this.accent,
    this.onAccent,
    this.background,
    this.incoming,
    this.incomingText,
    this.colorScheme,
    this.title,
  });

  factory HolloRemoteTheme.fromJson(Map<String, dynamic> json) {
    HolloRemoteColor? color(String key) {
      final pair = json[key];
      if (pair is! Map) return null;
      final light = readHexColor(pair['light']);
      final dark = readHexColor(pair['dark']);
      if (light == null && dark == null) return null;
      return HolloRemoteColor(light: light, dark: dark);
    }

    final scheme = json['colorScheme'];
    final title = readString(json['title'])?.trim() ?? '';
    return HolloRemoteTheme(
      accent: color('accent'),
      onAccent: color('onAccent'),
      background: color('background'),
      incoming: color('incoming'),
      incomingText: color('incomingText'),
      colorScheme: scheme == 'light' || scheme == 'dark' || scheme == 'system'
          ? scheme as String
          : null,
      title: title.isEmpty
          ? null
          : title.length > 40
              ? title.substring(0, 40)
              : title,
    );
  }

  /// The user's bubbles, the send button and filled buttons.
  final HolloRemoteColor? accent;

  /// Text and icons on accent surfaces.
  final HolloRemoteColor? onAccent;
  final HolloRemoteColor? background;

  /// Bubbles from the team and the AI.
  final HolloRemoteColor? incoming;
  final HolloRemoteColor? incomingText;

  /// `light` or `dark` forces that look; `system` (or null) leaves it to the
  /// app.
  final String? colorScheme;
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is HolloRemoteTheme &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.background == background &&
      other.incoming == incoming &&
      other.incomingText == incomingText &&
      other.colorScheme == colorScheme &&
      other.title == title;

  @override
  int get hashCode => Object.hash(
        accent,
        onAccent,
        background,
        incoming,
        incomingText,
        colorScheme,
        title,
      );
}

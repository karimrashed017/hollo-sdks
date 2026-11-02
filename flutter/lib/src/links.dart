import 'json.dart';

// Pure helpers, kept apart from the UI so they can be unit-tested.

/// The store page to leave a review on. [os] is `ios`, `android` or `web`.
String? reviewUrl(String os, Map<String, dynamic> payload) {
  final ios = readString(payload['appStoreId']);
  final android = readString(payload['playStorePackage']);
  if (os == 'android' && android != null) {
    return 'market://details?id=$android';
  }
  if (os == 'ios' && ios != null) {
    return 'itms-apps://itunes.apple.com/app/id$ios?action=write-review';
  }
  if (ios != null) {
    return 'https://apps.apple.com/app/id$ios?action=write-review';
  }
  if (android != null) {
    return 'https://play.google.com/store/apps/details?id=$android';
  }
  return null;
}

/// What tapping a link card does: open a URL, or one of the app's screens.
sealed class LinkAction {
  const LinkAction();
}

class UrlLinkAction extends LinkAction {
  const UrlLinkAction(this.url);

  final String url;
}

class ScreenLinkAction extends LinkAction {
  const ScreenLinkAction(this.screen, this.value);

  final String screen;
  final String? value;
}

// Never opened from a card, whatever the server sends.
final RegExp _blocked = RegExp(
  r'^(javascript|data|file|vbscript|blob):',
  caseSensitive: false,
);

LinkAction? linkAction(Map<String, dynamic> payload) {
  final url = readString(payload['url'])?.trim() ?? '';
  if (url.isNotEmpty) {
    return _blocked.hasMatch(url) ? null : UrlLinkAction(url);
  }
  final screen = readString(payload['screen']);
  if (screen == null) return null;
  return ScreenLinkAction(screen, readString(payload['value']));
}

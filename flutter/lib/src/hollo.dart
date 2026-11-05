import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'client.dart';
import 'links.dart';
import 'models.dart';
import 'paywalls.dart';
import 'storage.dart';
import 'store.dart';
import 'ui.dart';

// Public API: Hollo.start, present, identify, signOut, eraseUserData, the
// unread count, track, setSubscriber, push, and the embeddable HolloChat.

/// Hollo in-app support chat. Call [Hollo.start] once in `main()`.
abstract final class Hollo {
  static final HolloStore _store = HolloStore(
    // Read when needed, so the handler can be set before or after start.
    pushPermission: () => onPushPermission,
    onOpenRequested: _openFromSdk,
  );
  static String _os = 'web';
  static Route<void>? _route;

  /// Lets [present] open the chat without a BuildContext. Pass it to your
  /// app: `MaterialApp(navigatorKey: Hollo.navigatorKey, ...)`. If your app
  /// already has a navigator key, assign yours here instead.
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// The chat's look in light mode. Set it before the chat opens.
  static HolloTheme theme = HolloTheme.light;

  /// The chat's look in dark mode.
  static HolloTheme darkTheme = HolloTheme.dark;

  /// Follow the device (the default), or force light or dark.
  static ThemeMode themeMode = ThemeMode.system;

  /// Runs when the user taps an offer the team sent. Open your paywall or
  /// apply the discount for `offer.ref` here. The chat closes first.
  static void Function(HolloOffer offer)? onOffer;

  /// Opens [paywall] when the user taps an offer card, after the chat
  /// closes, and tracks how it ended (`offer_purchased`, `offer_declined`,
  /// ...) so automations can follow up. Replaces [onOffer].
  static void usePaywall(HolloPaywall paywall) {
    onOffer = (offer) async {
      final result = await runPaywall(paywall, offer.ref);
      await track('offer_${result.name}');
    };
  }

  /// Runs when the user taps a link card that opens one of your screens.
  /// Navigate to `link.screen` here (with `link.value`, if it has one).
  static void Function(HolloLink link)? onLink;

  /// Lets the chat ask for notifications after the user's first message, if
  /// the permission card is on in the dashboard. Ask the OS for permission
  /// here (with firebase_messaging, say) and return the FCM token, or null
  /// if the user said no.
  static Future<String?> Function()? onPushPermission;

  /// Opens review, store and web links. Replaced in tests.
  @visibleForTesting
  static Future<bool> Function(Uri uri) openUrl = _launch;

  /// Picks photos to attach. Replaced in tests.
  @visibleForTesting
  static HolloPhotoPicker pickPhotos = _pickPhotos;

  /// Live count of replies the user hasn't read, for your Support badge.
  static ValueListenable<int> get unreadCount => _store.unreadCount;

  /// Starts Hollo. Call it once, before `runApp`. It doesn't show anything
  /// or ask the user for anything, and the first fetch runs in the
  /// background.
  ///
  /// [apiUrl] is only for testing against a local server. [storage] keeps
  /// the device token (shared_preferences by default). [httpClient] is for
  /// tests and proxies.
  static Future<void> start({
    required String appKey,
    HolloTheme? theme,
    HolloTheme? darkTheme,
    String? apiUrl,
    HolloStorage? storage,
    http.Client? httpClient,
  }) async {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    if (theme != null) Hollo.theme = theme;
    if (darkTheme != null) Hollo.darkTheme = darkTheme;
    _os = _platform();
    final client = HolloClient(
      appKey: appKey,
      apiUrl: apiUrl,
      storage: storage ?? const SharedPreferencesHolloStorage(),
      platform: _os,
      httpClient: httpClient,
      info: {
        'os': kIsWeb ? 'web' : defaultTargetPlatform.name,
        // Review requests and other team messages use it to pick wording.
        'language': binding.platformDispatcher.locale.toLanguageTag(),
        'sdk': 'flutter $holloSdkVersion',
      },
    );
    unawaited(_store.start(client));
  }

  /// Opens the support chat over your app. Uses [navigatorKey], or the
  /// navigator above [context] when you pass one. Completes when the chat
  /// closes.
  static Future<void> present({BuildContext? context}) async {
    if (_route != null) return;
    final navigator = context != null
        ? Navigator.of(context, rootNavigator: true)
        : navigatorKey.currentState;
    if (navigator == null) {
      throw StateError(
        "Hollo.present() can't find a Navigator. Pass "
        'navigatorKey: Hollo.navigatorKey to your MaterialApp, or call '
        'Hollo.present(context: context).',
      );
    }
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const HolloChat(onClose: dismiss),
    );
    _route = route;
    try {
      await navigator.push(route);
    } finally {
      if (identical(_route, route)) _route = null;
    }
  }

  /// Closes the chat that [present] opened.
  static void dismiss() {
    final route = _route;
    _route = null;
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      route.navigator?.pop();
    } else {
      route.navigator?.removeRoute(route);
    }
  }

  /// Links this device to your app's user, so history follows them across
  /// devices. Call it after sign-in.
  ///
  /// Pass [identityToken] (an HMAC-SHA256 of [id], made by your server with
  /// the app's identity secret) to mark the user as verified.
  static Future<void> identify({
    required String id,
    String? name,
    String? email,
    String? identityToken,
  }) =>
      _store.identify(
        id: id,
        name: name,
        email: email,
        identityToken: identityToken,
      );

  /// Starts a fresh anonymous chat. The user's history stays on the server
  /// and comes back when they're identified again.
  static Future<void> signOut() => _store.signOut();

  /// Deletes the user's support data, for account-deletion flows. Throws if
  /// the device is offline or the request fails.
  static Future<void> eraseUserData() => _store.eraseUserData();

  /// Reports something the user did, like `paywall_declined`. Automations
  /// set up in the dashboard can reply, send an offer or open the chat.
  static Future<void> track(String name) => _store.track(name);

  /// Tells Hollo whether the user pays, for automation audiences and the AI.
  static Future<void> setSubscriber(bool isSubscriber) =>
      _store.setSubscriber(isSubscriber);

  /// Saves the device's Firebase Cloud Messaging token (from
  /// firebase_messaging; it covers iOS too), so replies reach the user when
  /// the chat is closed. Call it at every launch once the user has allowed
  /// notifications, and when the token refreshes. Pass null if they turn
  /// notifications off.
  static Future<void> registerPush(String? token) =>
      _store.registerPush(token);

  /// Pass a notification's data when the user taps it. Returns true and
  /// opens the chat if it was Hollo's, so your own notifications still
  /// reach you.
  static bool handle(Map<String, dynamic> data) {
    final flag = data['hollo'];
    final ours = flag == true || flag == 'true';
    if (ours) _openFromSdk();
    return ours;
  }

  /// Stops polling and forgets handlers, so each test starts clean.
  @visibleForTesting
  static void debugReset() {
    _store.close();
    _route = null;
    onOffer = null;
    onLink = null;
    onPushPermission = null;
    openUrl = _launch;
    pickPhotos = _pickPhotos;
    theme = HolloTheme.light;
    darkTheme = HolloTheme.dark;
    themeMode = ThemeMode.system;
    navigatorKey = GlobalKey<NavigatorState>();
  }

  static String _platform() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      // Desktop isn't a Hollo platform; the API files it with the web.
      _ => 'web',
    };
  }

  /// An automation or a tapped notification wants the chat open.
  static void _openFromSdk() {
    if (_route != null || _store.isOpen) return;
    if (navigatorKey.currentState == null) {
      // Launched from a notification: the app's navigator isn't built yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_presentQuietly());
      });
      return;
    }
    unawaited(_presentQuietly());
  }

  static Future<void> _presentQuietly() async {
    try {
      await present();
    } on StateError catch (error) {
      debugPrint('Hollo: ${error.message}');
    }
  }

  static void _offer(HolloOffer offer) {
    dismiss();
    onOffer?.call(offer);
  }

  // Links open a URL themselves; screens go to the app's onLink handler.
  static Future<void> _link(HolloMessage message) async {
    final action = linkAction(message.payload);
    final handler = onLink;
    if (action is UrlLinkAction) {
      final uri = Uri.tryParse(action.url);
      final opened = uri != null && await openUrl(uri);
      _store.linkTapped(message.id, opened);
    } else if (action is ScreenLinkAction && handler != null) {
      dismiss();
      handler(HolloLink(screen: action.screen, value: action.value));
      _store.linkTapped(message.id, true);
    } else {
      _store.linkTapped(message.id, false);
    }
  }

  // The system picker resizes and compresses, so a photo uploads in well
  // under the server's 4 MB, and on iOS it turns HEIC into JPEG, which the
  // server can't read. Android may hand back a PNG as it is; the server
  // takes those.
  static Future<List<Uint8List>> _pickPhotos(int limit) async {
    final picker = ImagePicker();
    final List<XFile> files;
    if (limit > 1) {
      files = await picker.pickMultiImage(
        limit: limit,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 70,
      );
    } else {
      // pickMultiImage needs a limit of at least 2.
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 70,
      );
      files = file == null ? const <XFile>[] : [file];
    }
    return Future.wait(files.take(limit).map((file) => file.readAsBytes()));
  }

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing on the device opens it, or the URL is malformed.
      return false;
    }
  }
}

/// The support chat as a widget, for placing in your own navigation (a tab,
/// say). It counts as open while it's on screen, so replies are marked read.
class HolloChat extends StatelessWidget {
  const HolloChat({super.key, this.onClose});

  /// Shows a Done button that calls this. [Hollo.present] sets it.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    // Rebuilt on every poll, so a look forced in the dashboard applies as
    // soon as it arrives.
    return ListenableBuilder(
      listenable: Hollo._store,
      builder: (context, _) {
        final dark = switch (Hollo._store.remoteTheme.colorScheme) {
          'dark' => true,
          'light' => false,
          _ => switch (Hollo.themeMode) {
              ThemeMode.dark => true,
              ThemeMode.light => false,
              ThemeMode.system =>
                MediaQuery.platformBrightnessOf(context) == Brightness.dark,
            },
        };
        return HolloChatView(
          store: Hollo._store,
          theme: dark ? Hollo.darkTheme : Hollo.theme,
          dark: dark,
          os: Hollo._os,
          onClose: onClose,
          onOffer: Hollo._offer,
          onLink: Hollo._link,
          // Looked up at tap time, so a replacement set later still applies.
          openUrl: (uri) => Hollo.openUrl(uri),
          pickPhotos: (limit) => Hollo.pickPhotos(limit),
        );
      },
    );
  }
}

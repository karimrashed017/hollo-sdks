import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cards.dart';
import 'client.dart';
import 'models.dart';

// The SDK's state: the conversation, the unread count and whether a chat is
// on screen, plus polling. A ChangeNotifier the chat widget listens to.

/// Asks the OS for notification permission and returns the push token, or
/// null when the user says no.
typedef HolloPushPermission = Future<String?> Function();

class HolloStore extends ChangeNotifier {
  HolloStore({
    this.openPoll = const Duration(seconds: 3),
    this.closedPoll = const Duration(seconds: 30),
    this.pushPermission,
    this.onOpenRequested,
  });

  /// How often to poll while a chat is on screen, and while none is.
  final Duration openPoll;
  final Duration closedPoll;

  /// Returns the app's permission handler. Read at the moment it's needed,
  /// so the app can set its handler any time.
  final HolloPushPermission? Function()? pushPermission;

  /// An automation or a notification wants the chat open.
  final VoidCallback? onOpenRequested;

  /// Replies the user hasn't seen, for the app's Support badge.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  HolloClient? _client;
  Timer? _timer;
  bool _closed = false;
  int _views = 0;
  String? _pushToken;

  List<HolloMessage> _messages = const <HolloMessage>[];
  bool _sending = false;
  String? _error;
  HolloProfile _profile = const HolloProfile();
  HolloPushSettings _push = const HolloPushSettings();
  HolloRemoteTheme _remoteTheme = const HolloRemoteTheme();
  bool _branding = true;
  bool _pushRegistered = false;
  bool _askPush = false;

  // Action confirm cards answered on this device, by confirmation ID. The
  // message itself never changes here, because polling only adds new ones.
  final Map<String, HolloConfirmState> _decided =
      <String, HolloConfirmState>{};
  final Set<String> _deciding = <String>{};
  final Map<String, String> _decideErrors = <String, String>{};

  bool get started => _client != null;

  /// A chat (presented or embedded) is on screen.
  bool get isOpen => _views > 0;

  List<HolloMessage> get messages => _messages;

  /// A message the user typed is still sending.
  bool get sending => _sending;

  /// The last poll or send failed. Polling keeps retrying.
  String? get error => _error;

  HolloProfile get profile => _profile;
  HolloPushSettings get push => _push;

  /// Colours and title from the dashboard, over the app's HolloTheme.
  HolloRemoteTheme get remoteTheme => _remoteTheme;

  /// Show the "Runs on Hollo" footer. The server decides.
  bool get branding => _branding;

  /// This device gave Hollo a push token.
  bool get pushRegistered => _pushRegistered;

  /// Show the in-chat card asking to turn on notifications (F-40).
  bool get askPush => _askPush;

  HolloClient get _api {
    final client = _client;
    if (client == null) {
      throw StateError("Call Hollo.start(appKey: '...') before using Hollo.");
    }
    return client;
  }

  /// Starts (or restarts) with [client]. Completes after the first poll.
  Future<void> start(HolloClient client) {
    _client = client;
    _closed = false;
    _messages = const <HolloMessage>[];
    _decided.clear();
    _decideErrors.clear();
    _error = null;
    unreadCount.value = 0;
    notifyListeners();
    return refresh();
  }

  /// Stops polling. [start] picks up again.
  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _client = null;
  }

  /// A chat came on screen. Opening one marks replies read.
  void chatShown() {
    _views++;
    if (_views == 1) _openChanged();
  }

  void chatHidden() {
    if (_views == 0) return;
    _views--;
    if (_views == 0) _openChanged();
  }

  void _openChanged() {
    final client = _client;
    if (client == null || _closed) return;
    if (isOpen) {
      unawaited(_quietly(client.markRead()));
      unreadCount.value = 0;
    }
    notifyListeners();
    // Poll right away, then at the open or closed pace.
    unawaited(refresh());
  }

  /// Fetches new messages, then schedules the next poll.
  Future<void> refresh() async {
    final client = _client;
    if (client == null || _closed) return;
    _timer?.cancel();
    try {
      final after = _messages.isEmpty ? null : _messages.last.createdAt;
      final page = await client.messages(after: after);
      // Restarted or signed out while this poll was in flight.
      if (!identical(client, _client)) return;
      if (page.open && !isOpen) onOpenRequested?.call();
      _profile = page.profile ?? _profile;
      _push = page.push ?? _push;
      _remoteTheme = page.theme ?? _remoteTheme;
      _branding = page.branding;
      _append(page.messages);
      if (isOpen) {
        if (page.unread > 0) unawaited(_quietly(client.markRead()));
        unreadCount.value = 0;
      } else {
        unreadCount.value = page.unread;
      }
      _error = null;
    } catch (error) {
      _error = error is HolloError ? error.message : error.toString();
    }
    notifyListeners();
    if (_closed || !identical(client, _client)) return;
    _timer?.cancel();
    _timer = Timer(isOpen ? openPoll : closedPoll, () => unawaited(refresh()));
  }

  void _append(Iterable<HolloMessage> incoming) {
    final known = {for (final message in _messages) message.id};
    final fresh = incoming.where((message) => known.add(message.id)).toList();
    if (fresh.isEmpty) return;
    _messages = List<HolloMessage>.unmodifiable([..._messages, ...fresh]);
  }

  /// Sends [body], with up to five [photos] (JPEG bytes from the picker).
  /// With photos the text is an optional caption. The photos upload first,
  /// so a failed upload sends nothing and the user can try again.
  Future<void> send(
    String body, {
    List<Uint8List> photos = const <Uint8List>[],
  }) async {
    final text = body.trim();
    if (text.isEmpty && photos.isEmpty) return;
    final client = _api;
    final first = !_messages.any((message) => message.fromUser);
    _sending = true;
    _error = null;
    notifyListeners();
    try {
      final paths = await Future.wait(
        photos.take(holloMaxPhotos).map(client.uploadPhoto),
      );
      _append([await client.send(text, photos: paths)]);
      if (first) unawaited(_maybeAskForPush());
    } catch (error) {
      _error = error is HolloError ? error.message : error.toString();
      rethrow;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Reports an event; automations may open the chat in response.
  Future<void> track(String name) async {
    final open = await _api.event(name: name);
    if (open && !isOpen) {
      onOpenRequested?.call();
    } else {
      unawaited(refresh());
    }
  }

  Future<void> setSubscriber(bool subscriber) async {
    await _api.event(subscriber: subscriber);
  }

  /// Saves the push token, or null when the user turns notifications off.
  Future<void> registerPush(String? token) async {
    _pushToken = token;
    await _api.registerPush(token);
    _pushRegistered = token != null;
    _askPush = false;
    notifyListeners();
  }

  /// Just after the first message: the moment a reply is worth waiting for.
  Future<void> _maybeAskForPush() async {
    if (_push.permissionCard == HolloPermissionCard.off || _pushRegistered) {
      return;
    }
    if (pushPermission?.call() == null) return;
    final client = _client;
    if (client == null || await client.getFlag('pushAsked')) return;
    _askPush = true;
    notifyListeners();
  }

  /// The user answered the card. Either way it never shows again.
  Future<void> answerPushCard(bool accept) async {
    _askPush = false;
    notifyListeners();
    final client = _client;
    if (client == null) return;
    await _quietly(client.setFlag('pushAsked'));
    final ask = pushPermission?.call();
    if (!accept || ask == null) return;
    String? token;
    try {
      token = await ask();
    } catch (_) {
      // The app's permission code failed; treat it as a no.
      return;
    }
    if (token != null) await _quietly(registerPush(token));
  }

  Future<void> identify({
    required String id,
    String? name,
    String? email,
    String? identityToken,
  }) async {
    await _api.identify(
      id: id,
      name: name,
      email: email,
      identityToken: identityToken,
    );
    await _reload();
  }

  /// Signing out starts a fresh anonymous chat; history stays on the server.
  Future<void> signOut() async {
    await _api.forgetDevice();
    await _reload();
  }

  /// Deletes this user's support data (App Store account-deletion rules).
  /// Throws if it fails, so the app can let the user try again.
  Future<void> eraseUserData() async {
    await _api.eraseUserData();
    await _reload();
  }

  /// An action confirm card's state, with any answer given here on top of
  /// what the server sent.
  HolloConfirmState confirmState(HolloConfirmation card) =>
      _decided[card.id] ?? card.state;

  /// The card's answer is on its way, so its buttons are off.
  bool isDeciding(String id) => _deciding.contains(id);

  /// Why the last answer to this card failed, or null.
  String? decideError(String id) => _decideErrors[id];

  /// The user tapped Confirm or Cancel. The card updates straight away; the
  /// AI's reply arrives with the next poll. Never throws.
  Future<void> answerConfirmation(String id, {required bool confirm}) async {
    final client = _client;
    if (client == null || _deciding.contains(id) || _decided.containsKey(id)) {
      return;
    }
    _deciding.add(id);
    _decideErrors.remove(id);
    notifyListeners();
    try {
      final status = await client.confirmAction(id, confirm: confirm);
      _decided[id] = status == 'cancelled'
          ? HolloConfirmState.cancelled
          : HolloConfirmState.confirmed;
    } on HolloError catch (error) {
      if (error.status == 409) {
        // Answered on another device, or it ran out of time.
        _decided[id] = HolloConfirmState.unavailable;
      } else {
        _decideErrors[id] = error.code == 'not_verified'
            ? 'Sign in to confirm this.'
            : "Couldn't send that. Try again.";
      }
    } catch (_) {
      _decideErrors[id] = "Couldn't send that. Try again.";
    } finally {
      _deciding.remove(id);
      notifyListeners();
    }
  }

  /// Reports a link card tap for the dashboard's counts. Never throws.
  void linkTapped(String messageId, bool opened) {
    final client = _client;
    if (client != null) {
      unawaited(_quietly(client.linkTapped(messageId, opened)));
    }
  }

  Future<void> _reload() async {
    _messages = const <HolloMessage>[];
    _decided.clear();
    _decideErrors.clear();
    unreadCount.value = 0;
    notifyListeners();
    // Signing in or out can mean a new device, which needs the token again.
    final token = _pushToken;
    if (token != null) await _quietly(registerPush(token));
    await refresh();
  }
}

/// Best effort: the next poll or call tries again.
Future<void> _quietly(Future<Object?> future) async {
  try {
    await future;
  } catch (_) {
    // Ignored on purpose; see above.
  }
}

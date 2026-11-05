import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'json.dart';
import 'models.dart';
import 'storage.dart';

// The Hollo HTTP client: no widgets, so it can be unit-tested with a mock
// http.Client. Talks to the SDK API at https://hollo.so/api/v1 with the app
// key and this install's device token.

const String holloSdkVersion = '0.1.7';
const String holloApiUrl = 'https://hollo.so/api/v1';

/// The most photos one message can carry (F-17).
const int holloMaxPhotos = 5;

/// The server refuses bigger uploads. The picker's resizing and compression
/// keep a real photo far below it.
const int holloMaxPhotoBytes = 4 * 1024 * 1024;

/// A failed Hollo call. [code] is the API's error code, like
/// `plan_required`, or `network_error` when Hollo couldn't be reached.
class HolloError implements Exception {
  const HolloError(this.code, this.message, this.status);

  final String code;
  final String message;

  /// The HTTP status, or 0 when the request never got an answer.
  final int status;

  @override
  String toString() => 'HolloError($code): $message';
}

/// One poll of GET /messages.
class HolloMessagesResponse {
  const HolloMessagesResponse({
    required this.messages,
    required this.unread,
    this.profile,
    this.push,
    this.open = false,
    this.branding = true,
    this.theme,
  });

  final List<HolloMessage> messages;
  final int unread;
  final HolloProfile? profile;
  final HolloPushSettings? push;

  /// An automation asked to open the chat.
  final bool open;

  /// Show "Runs on Hollo" under the composer. Missing means yes.
  final bool branding;

  /// Dashboard colours and title. Servers before 0.1.4 leave it out.
  final HolloRemoteTheme? theme;
}

class HolloClient {
  HolloClient({
    required this.appKey,
    required this.storage,
    required this.platform,
    this.info = const <String, String>{},
    String? apiUrl,
    http.Client? httpClient,
  })  : apiUrl = (apiUrl ?? holloApiUrl).replaceFirst(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client();

  final String appKey;
  final HolloStorage storage;

  /// `ios`, `android` or `web`, as POST /devices expects.
  final String platform;

  /// OS, language and SDK version, sent once when the device registers.
  final Map<String, String> info;
  final String apiUrl;
  final http.Client _http;
  Future<String>? _token;

  String get _tokenKey => 'hollo.deviceToken.$appKey';

  /// The device token, registering this install the first time. Calls made
  /// at the same moment share one registration.
  Future<String> _deviceToken() => _token ??= _loadOrRegister();

  Future<String> _loadOrRegister() async {
    try {
      final saved = await storage.getItem(_tokenKey);
      if (saved != null && saved.isNotEmpty) return saved;
      final data = await _call(
        'POST',
        '/devices',
        body: {'platform': platform, 'info': info},
        auth: false,
      );
      final token = readString(data['deviceToken']);
      if (token == null) {
        throw const HolloError('server_error', 'Hollo sent no device token.', 0);
      }
      await storage.setItem(_tokenKey, token);
      return token;
    } catch (_) {
      // Let the next call try again.
      _token = null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Object? body,
    Uint8List? bytes,
    String? contentType,
    bool auth = true,
    bool retried = false,
  }) async {
    final request = http.Request(method, Uri.parse('$apiUrl$path'));
    request.headers['x-hollo-app-key'] = appKey;
    if (auth) {
      request.headers['authorization'] = 'Bearer ${await _deviceToken()}';
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    } else if (bytes != null) {
      // A raw upload: a photo.
      request.headers['content-type'] =
          contentType ?? 'application/octet-stream';
      request.bodyBytes = bytes;
    }

    final http.Response response;
    try {
      final streamed =
          await _http.send(request).timeout(const Duration(seconds: 30));
      response = await http.Response.fromStream(streamed);
    } on Exception catch (error) {
      throw HolloError('network_error', "Couldn't reach Hollo: $error", 0);
    }

    var data = <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } on FormatException {
      // Not JSON (a proxy's error page, say): the status check below handles it.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = readMap(data['error']);
      final code = readString(error['code']) ?? 'network_error';
      // The server forgot this device (its data was erased, say): register
      // again and retry once.
      if (code == 'invalid_device' && auth && !retried) {
        await forgetDevice();
        return _call(
          method,
          path,
          body: body,
          bytes: bytes,
          contentType: contentType,
          auth: auth,
          retried: true,
        );
      }
      throw HolloError(
        code,
        readString(error['message']) ??
            'Request failed (${response.statusCode})',
        response.statusCode,
      );
    }
    return data;
  }

  /// Drops the device token, so the next call registers a fresh device.
  Future<void> forgetDevice() async {
    _token = null;
    await storage.removeItem(_tokenKey);
  }

  /// Links this device to the app's user. Returns Hollo's user ID and
  /// whether the identity token checked out (false when it's missing).
  Future<({String? userId, bool verified})> identify({
    required String id,
    String? name,
    String? email,
    String? identityToken,
  }) async {
    final data = await _call(
      'POST',
      '/identify',
      body: {
        'id': id,
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (identityToken != null) 'token': identityToken,
      },
    );
    return (
      userId: readString(data['userId']),
      verified: data['verified'] == true,
    );
  }

  /// The conversation, or only messages newer than [after] when polling.
  Future<HolloMessagesResponse> messages({String? after}) async {
    final query = after == null || after.isEmpty
        ? ''
        : '?after=${Uri.encodeComponent(after)}';
    final data = await _call('GET', '/messages$query');
    final raw = data['messages'];
    final unread = data['unread'];
    return HolloMessagesResponse(
      messages: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(HolloMessage.fromJson)
              .toList()
          : const <HolloMessage>[],
      unread: unread is num ? unread.toInt() : 0,
      profile: data['profile'] is Map
          ? HolloProfile.fromJson(readMap(data['profile']))
          : null,
      push: data['push'] is Map
          ? HolloPushSettings.fromJson(readMap(data['push']))
          : null,
      open: data['open'] == true,
      branding: data['branding'] != false,
      theme: data['theme'] is Map
          ? HolloRemoteTheme.fromJson(readMap(data['theme']))
          : null,
    );
  }

  /// Sends a message. [photos] are paths from [uploadPhoto]; with photos the
  /// text is an optional caption.
  Future<HolloMessage> send(
    String body, {
    List<String> photos = const <String>[],
  }) async {
    final data = await _call(
      'POST',
      '/messages',
      body: {
        if (body.isNotEmpty || photos.isEmpty) 'body': body,
        if (photos.isNotEmpty) 'photos': photos,
      },
    );
    return HolloMessage.fromJson(readMap(data['message']));
  }

  /// Uploads one photo, already resized and compressed on the device, and
  /// returns its path for [send]. The server checks the bytes themselves, so
  /// a PNG the Android picker leaves as it is works too.
  Future<String> uploadPhoto(Uint8List jpeg) async {
    if (jpeg.length > holloMaxPhotoBytes) {
      // The server would refuse it; don't spend the user's data finding out.
      throw const HolloError(
        'photo_too_large',
        'Photos can be up to 4 MB.',
        0,
      );
    }
    final data = await _call(
      'POST',
      '/photos',
      bytes: jpeg,
      contentType: 'image/jpeg',
    );
    final path = readString(readMap(data['photo'])['path']);
    if (path == null) {
      throw const HolloError('server_error', 'Hollo sent no photo path.', 0);
    }
    return path;
  }

  /// Counts a link card tap. [opened] is false when nothing could open it.
  Future<void> linkTapped(String messageId, bool opened) async {
    await _call(
      'POST',
      '/links/tap',
      body: {'messageId': messageId, 'opened': opened},
    );
  }

  /// Answers an action confirm card. Returns `confirmed` or `cancelled`.
  /// A card already answered or expired throws with status 409.
  Future<String> confirmAction(String id, {required bool confirm}) async {
    final data = await _call(
      'POST',
      '/confirmations',
      body: {'id': id, 'decision': confirm ? 'confirm' : 'cancel'},
    );
    return readString(data['status']) ?? (confirm ? 'confirmed' : 'cancelled');
  }

  /// Reports an event (Hollo.track) or the subscription status. Returns
  /// true when an automation wants the chat open now.
  Future<bool> event({String? name, bool? subscriber}) async {
    final data = await _call(
      'POST',
      '/events',
      body: {
        if (name != null) 'name': name,
        if (subscriber != null) 'subscriber': subscriber,
      },
    );
    return data['open'] == true;
  }

  /// Saves the push token, or null to stop notifications. Flutter apps hand
  /// over a Firebase Cloud Messaging token, which covers iOS too.
  Future<void> registerPush(String? token, {String provider = 'fcm'}) async {
    await _call(
      'POST',
      '/push',
      body: {'token': token, 'provider': provider},
    );
  }

  /// Clears the unread count. Returns the new count (0).
  Future<int> markRead() async {
    final data = await _call('POST', '/read');
    final unread = data['unread'];
    return unread is num ? unread.toInt() : 0;
  }

  /// Deletes the user's support data, then forgets this device.
  Future<void> eraseUserData() async {
    await _call('DELETE', '/user');
    await forgetDevice();
  }

  /// Small flags kept beside the device token, like "asked for push".
  Future<bool> getFlag(String name) async =>
      await storage.getItem('hollo.$name.$appKey') != null;

  Future<void> setFlag(String name) =>
      storage.setItem('hollo.$name.$appKey', '1');

  void close() => _http.close();
}

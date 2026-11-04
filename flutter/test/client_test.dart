import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollo/src/client.dart';
import 'package:hollo/src/models.dart';
import 'package:hollo/src/storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

const storage = SharedPreferencesHolloStorage();
const tokenKey = 'hollo.deviceToken.$appKey';

HolloClient clientFor(http.Client httpClient) => HolloClient(
      appKey: appKey,
      storage: storage,
      platform: 'ios',
      info: const {'sdk': 'flutter test'},
      httpClient: httpClient,
    );

Map<String, Object?> bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HolloClient', () {
    test('registers once, then sends the device token on every call',
        () async {
      var registrations = 0;
      final server = FakeServer({
        'POST /devices': (_) {
          registrations++;
          return reply(201, {
            'deviceToken': 'hdt_first_token_value_1234',
            'userId': 'u1',
          });
        },
        'GET /messages': (_) => reply(200, {'messages': [], 'unread': 0}),
      });
      final api = clientFor(server.client);

      // Two calls at once still share one registration.
      await Future.wait([api.messages(), api.messages()]);
      await api.messages();

      expect(registrations, 1);
      final register = server.to('POST', '/devices').single;
      expect(register.headers['x-hollo-app-key'], appKey);
      expect(register.headers.containsKey('authorization'), isFalse);
      expect(bodyOf(register), {
        'platform': 'ios',
        'info': {'sdk': 'flutter test'},
      });

      final last = server.calls.last;
      expect(last.headers['x-hollo-app-key'], appKey);
      expect(last.headers['authorization'], 'Bearer hdt_first_token_value_1234');
      expect(await storage.getItem(tokenKey), 'hdt_first_token_value_1234');
    });

    test('reuses a token saved by an earlier launch', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'GET /messages': (_) => reply(200, {'messages': [], 'unread': 2}),
      });

      final page = await clientFor(server.client).messages();

      expect(page.unread, 2);
      expect(page.branding, isTrue, reason: 'missing means show it');
      expect(server.to('POST', '/devices'), isEmpty);
      expect(
        server.calls.single.headers['authorization'],
        'Bearer hdt_saved_token_value_1234',
      );
    });

    test('registers again when the server has forgotten the device', () async {
      await storage.setItem(tokenKey, 'hdt_old_token_value_123456');
      final server = FakeServer({
        'GET /messages': (request) =>
            request.headers['authorization'] ==
                    'Bearer hdt_old_token_value_123456'
                ? reply(401, {
                    'error': {'code': 'invalid_device', 'message': 'Unknown'},
                  })
                : reply(200, {'messages': [], 'unread': 0}),
        'POST /devices': (_) =>
            reply(201, {'deviceToken': 'hdt_new_token_value_123456'}),
      });

      await clientFor(server.client).messages();

      expect(await storage.getItem(tokenKey), 'hdt_new_token_value_123456');
      expect(server.to('GET', '/messages'), hasLength(2));
      expect(
        server.calls.last.headers['authorization'],
        'Bearer hdt_new_token_value_123456',
      );
    });

    test('retries invalid_device only once', () async {
      final server = FakeServer({
        'POST /devices': (_) =>
            reply(201, {'deviceToken': 'hdt_any_token_value_123456'}),
        'GET /messages': (_) => reply(401, {
              'error': {'code': 'invalid_device', 'message': 'Unknown'},
            }),
      });

      await expectLater(
        clientFor(server.client).messages(),
        throwsA(isA<HolloError>().having((e) => e.code, 'code', 'invalid_device')),
      );
      expect(server.to('GET', '/messages'), hasLength(2));
    });

    test('surfaces a missing plan as a clear error', () async {
      final server = FakeServer({
        'POST /devices': (_) => reply(402, {
              'error': {'code': 'plan_required', 'message': 'No plan'},
            }),
      });

      await expectLater(
        clientFor(server.client).messages(),
        throwsA(
          isA<HolloError>()
              .having((e) => e.code, 'code', 'plan_required')
              .having((e) => e.message, 'message', 'No plan')
              .having((e) => e.status, 'status', 402),
        ),
      );
    });

    test('maps a body that is not JSON to the status code', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final api = clientFor(
        MockClient((_) async => http.Response('<html>Bad gateway</html>', 502)),
      );

      await expectLater(
        api.messages(),
        throwsA(
          isA<HolloError>()
              .having((e) => e.code, 'code', 'network_error')
              .having((e) => e.message, 'message', 'Request failed (502)')
              .having((e) => e.status, 'status', 502),
        ),
      );
    });

    test('reports being offline as network_error, then tries again', () async {
      var online = false;
      final api = clientFor(
        MockClient((request) async {
          if (!online) throw http.ClientException('offline', request.url);
          return request.url.path.endsWith('/devices')
              ? reply(201, {'deviceToken': 'hdt_later_token_value_1234'})
              : reply(200, {'messages': [], 'unread': 1});
        }),
      );

      await expectLater(
        api.messages(),
        throwsA(
          isA<HolloError>()
              .having((e) => e.code, 'code', 'network_error')
              .having((e) => e.status, 'status', 0),
        ),
      );
      online = true;
      expect((await api.messages()).unread, 1);
    });

    test('parses messages, the profile and push settings', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'GET /messages': (_) => reply(200, {
              'messages': [
                message('1', 'team', 'Hi!'),
                message(
                  '2',
                  'team',
                  '',
                  kind: 'offer',
                  payload: {'title': 'Half price', 'ref': 'yearly_50'},
                ),
              ],
              'unread': 2,
              'profile': {
                'name': 'Karim',
                'role': 'Founder',
                'photo': 'http://insecure.example/photo.png',
                'welcome': 'Ask me anything',
              },
              'push': {'permissionCard': 'replies_offers', 'notifyLine': false},
              'open': true,
              'branding': false,
            }),
      });

      final page = await clientFor(server.client).messages();

      expect(page.messages.map((m) => m.id), ['1', '2']);
      expect(page.messages.first.sender, 'team');
      expect(page.messages.first.createdAt, '2026-11-02T10:00:01.000000+00:00');
      expect(page.messages.last.kind, 'offer');
      expect(page.messages.last.payload['ref'], 'yearly_50');
      expect(page.profile?.name, 'Karim');
      expect(page.profile?.photo, isNull, reason: 'only https photos');
      expect(page.profile?.welcome, 'Ask me anything');
      expect(page.push?.permissionCard, HolloPermissionCard.repliesOffers);
      expect(page.push?.notifyLine, isFalse);
      expect(page.open, isTrue);
      expect(page.branding, isFalse);
      expect(page.theme, isNull, reason: 'older servers send no theme');
    });

    test('parses a full dashboard theme', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'GET /messages': (_) => reply(200, {
              'messages': [],
              'unread': 0,
              'theme': {
                'accent': {'light': '#FF5500', 'dark': '#ffaa77'},
                'onAccent': {'light': '#FFFFFF', 'dark': '#000000'},
                'background': {'light': '#FAFAFA', 'dark': '#101010'},
                'incoming': {'light': '#EEEEEE', 'dark': '#222222'},
                'incomingText': {'light': '#111111', 'dark': '#F0F0F0'},
                'colorScheme': 'dark',
                'title': '  Driftwood help  ',
              },
            }),
      });

      final theme = (await clientFor(server.client).messages()).theme;

      expect(
        theme,
        const HolloRemoteTheme(
          accent: HolloRemoteColor(light: 0xFFFF5500, dark: 0xFFFFAA77),
          onAccent: HolloRemoteColor(light: 0xFFFFFFFF, dark: 0xFF000000),
          background: HolloRemoteColor(light: 0xFFFAFAFA, dark: 0xFF101010),
          incoming: HolloRemoteColor(light: 0xFFEEEEEE, dark: 0xFF222222),
          incomingText: HolloRemoteColor(light: 0xFF111111, dark: 0xFFF0F0F0),
          colorScheme: 'dark',
          title: 'Driftwood help',
        ),
      );
    });

    test('a partial theme keeps only what is set', () {
      final theme = HolloRemoteTheme.fromJson(const {
        'accent': {'dark': '#123456'},
        'colorScheme': 'system',
      });
      expect(
        theme,
        const HolloRemoteTheme(
          accent: HolloRemoteColor(dark: 0xFF123456),
          colorScheme: 'system',
        ),
      );
      // Only dark is set, so the light look keeps the app's accent.
      expect(theme.accent?.pick(dark: true), 0xFF123456);
      expect(theme.accent?.pick(dark: false), isNull);
    });

    test('malformed theme values are dropped', () async {
      final theme = HolloRemoteTheme.fromJson(const {
        'accent': '#FF5500',
        'onAccent': {'light': '#FFF', 'dark': 12},
        'background': {'light': '#GG0000', 'dark': '#00000080'},
        'incoming': null,
        'incomingText': {'light': '#+12345'},
        'colorScheme': 'sepia',
        'title': '   ',
      });
      expect(theme, const HolloRemoteTheme());

      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'GET /messages': (_) =>
            reply(200, {'messages': [], 'unread': 2, 'theme': 'blue'}),
      });
      final page = await clientFor(server.client).messages();
      expect(page.theme, isNull);
      expect(page.unread, 2);
    });

    test('polls with the last message time, encoded', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'GET /messages': (_) => reply(200, {'messages': [], 'unread': 0}),
      });

      await clientFor(server.client)
          .messages(after: '2026-11-02T10:00:00.123456+00:00');

      // Unencoded, the "+" would arrive as a space.
      expect(
        server.calls.single.url.queryParameters['after'],
        '2026-11-02T10:00:00.123456+00:00',
      );
    });

    test('sends identify without empty fields', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'POST /identify': (_) => reply(200, {'userId': 'u42'}),
      });

      final identified = await clientFor(server.client).identify(id: 'user_42');

      expect(identified.userId, 'u42');
      expect(identified.verified, isFalse);
      expect(bodyOf(server.calls.single), {'id': 'user_42'});
      expect(server.calls.single.headers['content-type'], contains('application/json'));
    });

    test('sends the identity token only when given', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'POST /identify': (_) => reply(200, {'userId': 'u42', 'verified': true}),
      });

      final identified = await clientFor(server.client)
          .identify(id: 'user_42', identityToken: 'a1b2c3');

      expect(identified.verified, isTrue);
      expect(bodyOf(server.calls.single), {'id': 'user_42', 'token': 'a1b2c3'});
    });

    test('sends the FCM push token, and null to turn push off', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'POST /push': (_) => reply(200, {'ok': true}),
      });
      final api = clientFor(server.client);

      await api.registerPush('fcm-token-123');
      await api.registerPush(null);

      final bodies = server.to('POST', '/push').map(bodyOf).toList();
      expect(bodies, [
        {'token': 'fcm-token-123', 'provider': 'fcm'},
        {'token': null, 'provider': 'fcm'},
      ]);
    });

    test('erasing user data forgets the device token', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'DELETE /user': (_) => reply(200, {'deleted': true}),
      });

      await clientFor(server.client).eraseUserData();

      expect(await storage.getItem(tokenKey), isNull);
    });

    test('erasing user data throws when it fails', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'DELETE /user': (_) => reply(500, {
              'error': {'code': 'server_error', 'message': 'Try again'},
            }),
      });

      await expectLater(
        clientFor(server.client).eraseUserData(),
        throwsA(isA<HolloError>()),
      );
      expect(await storage.getItem(tokenKey), 'hdt_saved_token_value_1234');
    });

    test('reports link taps and events', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'POST /links/tap': (_) => reply(200, {'ok': true}),
        'POST /events': (request) =>
            reply(200, {'open': bodyOf(request)['name'] == 'paywall_declined'}),
      });
      final api = clientFor(server.client);

      await api.linkTapped('m1', false);
      expect(await api.event(name: 'paywall_declined'), isTrue);
      expect(await api.event(subscriber: true), isFalse);

      expect(bodyOf(server.to('POST', '/links/tap').single), {
        'messageId': 'm1',
        'opened': false,
      });
      expect(bodyOf(server.to('POST', '/events').last), {'subscriber': true});
    });
  });

  group('Photos', () {
    // A JPEG's first bytes, which is all the fake server needs.
    final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
    const path = 'w/c/abcdefghijklmnop.jpg';

    test('uploads the raw JPEG bytes with the device token', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'POST /photos': (_) => reply(201, {
              'photo': {'path': path},
            }),
      });

      expect(await clientFor(server.client).uploadPhoto(jpeg), path);

      final upload = server.to('POST', '/photos').single;
      expect(upload.headers['content-type'], 'image/jpeg');
      expect(upload.headers['x-hollo-app-key'], appKey);
      expect(upload.headers['authorization'], 'Bearer hdt_saved_token_value_1234');
      expect(upload.bodyBytes, jpeg);
    });

    test('uploads again with a new device when the old one is forgotten',
        () async {
      await storage.setItem(tokenKey, 'hdt_old_token_value_123456');
      final server = FakeServer({
        'POST /photos': (request) =>
            request.headers['authorization'] ==
                    'Bearer hdt_old_token_value_123456'
                ? reply(401, {
                    'error': {'code': 'invalid_device', 'message': 'Unknown'},
                  })
                : reply(201, {
                    'photo': {'path': path},
                  }),
        'POST /devices': (_) =>
            reply(201, {'deviceToken': 'hdt_new_token_value_123456'}),
      });

      expect(await clientFor(server.client).uploadPhoto(jpeg), path);

      final uploads = server.to('POST', '/photos');
      expect(uploads, hasLength(2));
      expect(uploads.last.bodyBytes, jpeg, reason: 'the retry keeps the bytes');
      expect(uploads.last.headers['content-type'], 'image/jpeg');
    });

    test('surfaces the server refusing a photo', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'POST /photos': (_) => reply(415, {
              'error': {'code': 'unsupported_photo', 'message': 'Not a photo'},
            }),
      });

      await expectLater(
        clientFor(server.client).uploadPhoto(jpeg),
        throwsA(
          isA<HolloError>()
              .having((e) => e.code, 'code', 'unsupported_photo')
              .having((e) => e.status, 'status', 415),
        ),
      );
    });

    test('refuses a photo over 4 MB without sending it', () async {
      final server = FakeServer({});

      await expectLater(
        clientFor(server.client)
            .uploadPhoto(Uint8List(holloMaxPhotoBytes + 1)),
        throwsA(
          isA<HolloError>().having((e) => e.code, 'code', 'photo_too_large'),
        ),
      );
      expect(server.calls, isEmpty);
    });

    test('sends photo paths with an optional caption', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'POST /messages': (_) => reply(201, {
              'message': message(
                '1',
                'end_user',
                '',
                kind: 'image',
                payload: {
                  'photos': [path],
                },
              ),
            }),
      });
      final api = clientFor(server.client);

      await api.send('', photos: [path]);
      await api.send('The error', photos: [path, path]);
      await api.send('Just text');

      final sent = server.to('POST', '/messages').map(bodyOf).toList();
      expect(sent[0], {
        'photos': [path],
      });
      expect(sent[1], {
        'body': 'The error',
        'photos': [path, path],
      });
      expect(sent[2], {'body': 'Just text'});
    });

    test('reads photo URLs, and none from older servers', () async {
      await storage.setItem(tokenKey, 'hdt_saved_token_value_1234');
      final server = FakeServer({
        'GET /messages': (_) => reply(200, {
              'messages': [
                {
                  ...message(
                    '1',
                    'end_user',
                    'See this',
                    kind: 'image',
                    payload: {
                      'photos': [path, path],
                    },
                  ),
                  'photos': [
                    'https://cdn.example/1.jpg?token=a',
                    'javascript:alert(1)',
                    42,
                    'https://cdn.example/2.jpg?token=b',
                  ],
                },
                message('2', 'team', 'Thanks'),
                {...message('3', 'end_user', ''), 'photos': 'not a list'},
              ],
              'unread': 0,
            }),
      });

      final page = await clientFor(server.client).messages();

      expect(page.messages[0].kind, 'image');
      expect(page.messages[0].body, 'See this');
      expect(page.messages[0].photos, [
        'https://cdn.example/1.jpg?token=a',
        'https://cdn.example/2.jpg?token=b',
      ]);
      expect(page.messages[1].photos, isEmpty);
      expect(page.messages[2].photos, isEmpty);
    });
  });
}

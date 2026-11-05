import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollo/src/cards.dart';
import 'package:hollo/src/client.dart';
import 'package:hollo/src/models.dart';
import 'package:hollo/src/storage.dart';
import 'package:hollo/src/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

HolloClient clientFor(FakeServer server) => HolloClient(
      appKey: appKey,
      storage: const SharedPreferencesHolloStorage(),
      platform: 'android',
      httpClient: server.client,
    );

FakeRoute registered() =>
    (_) => reply(201, {'deviceToken': 'hdt_store_token_value_1234'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unread follows the server, and opening the chat clears it', () async {
    var unread = 2;
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (_) => reply(200, {'messages': [], 'unread': unread}),
      'POST /read': (_) {
        unread = 0;
        return reply(200, {'unread': 0});
      },
    });
    final store = HolloStore();
    addTearDown(store.close);
    final counts = <int>[];
    store.unreadCount.addListener(() => counts.add(store.unreadCount.value));

    await store.start(clientFor(server));
    expect(store.unreadCount.value, 2);

    store.chatShown();
    expect(store.unreadCount.value, 0);
    await settle();
    expect(server.to('POST', '/read'), isNotEmpty);

    store.chatHidden();
    await settle();
    unread = 1;
    await store.refresh();
    expect(store.unreadCount.value, 1);
    expect(counts, [2, 0, 1]);
  });

  test('keeps the last dashboard theme until a new one arrives', () async {
    Object? theme = {
      'accent': {'light': '#FF5500'},
      'title': 'Help',
    };
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (_) => reply(200, {
            'messages': [],
            'unread': 0,
            if (theme != null) 'theme': theme,
          }),
    });
    final store = HolloStore();
    addTearDown(store.close);
    expect(store.remoteTheme, const HolloRemoteTheme());

    await store.start(clientFor(server));
    expect(store.remoteTheme.accent?.light, 0xFFFF5500);
    expect(store.remoteTheme.title, 'Help');

    // A server without the field leaves the last theme in place.
    theme = null;
    await store.refresh();
    expect(store.remoteTheme.title, 'Help');

    // An empty one clears it: the dashboard settings were removed.
    theme = <String, Object?>{};
    await store.refresh();
    expect(store.remoteTheme, const HolloRemoteTheme());
  });

  test('new messages are added once, in order', () async {
    final first = message('1', 'team', 'Hi!');
    final second = message('2', 'ai', 'How can I help?');
    final third = message('3', 'team', 'Still there?');
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (request) => reply(200, {
            'messages': request.url.queryParameters['after'] == null
                ? [first, second]
                : [second, third],
            'unread': 0,
          }),
    });
    final store = HolloStore();
    addTearDown(store.close);

    await store.start(clientFor(server));
    expect(store.messages.map((m) => m.id), ['1', '2']);

    await store.refresh();
    expect(store.messages.map((m) => m.id), ['1', '2', '3']);
    expect(
      server.to('GET', '/messages').last.url.queryParameters['after'],
      second['created_at'],
    );
  });

  test('an automation can open the chat', () async {
    var opens = 0;
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (_) =>
          reply(200, {'messages': [], 'unread': 0, 'open': true}),
      'POST /events': (_) => reply(200, {'open': true}),
    });
    final store = HolloStore(onOpenRequested: () => opens++);
    addTearDown(store.close);

    await store.start(clientFor(server));
    expect(opens, 1);

    await store.track('paywall_declined');
    expect(opens, 2);
    expect(
      jsonDecode(server.to('POST', '/events').single.body),
      {'name': 'paywall_declined'},
    );
  });

  test('a failed send keeps the error and rethrows', () async {
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (_) => reply(200, {'messages': [], 'unread': 0}),
      'POST /messages': (_) => reply(400, {
            'error': {'code': 'empty_message', 'message': 'body is required.'},
          }),
    });
    final store = HolloStore();
    addTearDown(store.close);
    await store.start(clientFor(server));

    await expectLater(store.send('Hello'), throwsA(isA<HolloError>()));
    expect(store.error, 'body is required.');
    expect(store.sending, isFalse);
    expect(store.messages, isEmpty);
  });

  test('uploads photos, then sends their paths in order', () async {
    var uploads = 0;
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (_) => reply(200, {'messages': [], 'unread': 0}),
      'POST /photos': (request) => reply(201, {
            'photo': {'path': 'p${request.bodyBytes.first}-${uploads++}.jpg'},
          }),
      'POST /messages': (request) => reply(201, {
            'message': {
              ...message('9', 'end_user', ''),
              'kind': 'image',
              'photos': ['https://cdn.example/1.jpg'],
            },
          }),
    });
    final store = HolloStore();
    addTearDown(store.close);
    await store.start(clientFor(server));

    await store.send(
      '  ',
      photos: [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ],
    );

    expect(server.to('POST', '/photos'), hasLength(2));
    final sent =
        jsonDecode(server.to('POST', '/messages').single.body) as Map;
    expect(sent.containsKey('body'), isFalse, reason: 'no caption');
    expect(
      (sent['photos'] as List).map((p) => (p as String).substring(0, 2)),
      ['p1', 'p2'],
    );
    expect(store.messages.single.photos, ['https://cdn.example/1.jpg']);
  });

  test('a failed upload sends nothing and rethrows', () async {
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (_) => reply(200, {'messages': [], 'unread': 0}),
      'POST /photos': (_) => reply(415, {
            'error': {'code': 'unsupported_photo', 'message': 'Not a photo'},
          }),
    });
    final store = HolloStore();
    addTearDown(store.close);
    await store.start(clientFor(server));

    await expectLater(
      store.send('Look', photos: [Uint8List.fromList([1])]),
      throwsA(isA<HolloError>()),
    );
    expect(store.error, 'Not a photo');
    expect(store.sending, isFalse);
    expect(server.to('POST', '/messages'), isEmpty);
  });

  test('after the first message, asks for push and saves the FCM token',
      () async {
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (_) => reply(200, {
            'messages': [],
            'unread': 0,
            'push': {'permissionCard': 'replies', 'notifyLine': true},
          }),
      'POST /messages': (request) => reply(201, {
            'message': message('9', 'end_user', 'Hello'),
          }),
      'POST /push': (_) => reply(200, {'ok': true}),
    });
    final store = HolloStore(
      pushPermission: () => () async => 'fcm-token-abc',
    );
    addTearDown(store.close);
    await store.start(clientFor(server));

    await store.send('Hello');
    await settle();
    expect(store.messages.single.body, 'Hello');
    expect(store.askPush, isTrue);

    await store.answerPushCard(true);
    expect(store.askPush, isFalse);
    expect(store.pushRegistered, isTrue);
    expect(jsonDecode(server.to('POST', '/push').single.body), {
      'token': 'fcm-token-abc',
      'provider': 'fcm',
    });
  });

  test('without a permission handler, the push card never shows', () async {
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (_) => reply(200, {
            'messages': [],
            'unread': 0,
            'push': {'permissionCard': 'replies'},
          }),
      'POST /messages': (_) => reply(201, {
            'message': message('9', 'end_user', 'Hello'),
          }),
    });
    final store = HolloStore();
    addTearDown(store.close);
    await store.start(clientFor(server));

    await store.send('Hello');
    await settle();
    expect(store.askPush, isFalse);
  });

  test('signing out starts a fresh device and an empty chat', () async {
    var registrations = 0;
    final server = FakeServer({
      'POST /devices': (_) {
        registrations++;
        return reply(201, {'deviceToken': 'hdt_device_${registrations}_token_value'});
      },
      'GET /messages': (request) => reply(200, {
            'messages': request.headers['authorization']!.contains('_1_')
                ? [message('1', 'team', 'Hi!')]
                : [],
            'unread': 0,
          }),
    });
    final store = HolloStore();
    addTearDown(store.close);
    await store.start(clientFor(server));
    expect(store.messages, hasLength(1));

    await store.signOut();
    expect(registrations, 2);
    expect(store.messages, isEmpty);
  });

  test('answers confirm cards, and locks them when the server says no',
      () async {
    const first = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
    const second = '0f8fad5b-d9cb-469f-a165-70867728950e';
    var failNext = true;
    final server = FakeServer({
      'POST /devices': registered(),
      'GET /messages': (_) => reply(200, {'messages': [], 'unread': 0}),
      'POST /confirmations': (request) {
        final fields = jsonDecode(request.body) as Map<String, Object?>;
        if (fields['id'] == second) {
          return reply(409, {
            'error': {'code': 'not_pending', 'message': 'Already answered.'},
          });
        }
        if (failNext) {
          failNext = false;
          return reply(500, {
            'error': {'code': 'server_error', 'message': 'Oops'},
          });
        }
        return reply(200, {'status': 'confirmed'});
      },
    });
    final store = HolloStore();
    addTearDown(store.close);
    await store.start(clientFor(server));
    const card = HolloConfirmation(
      id: first,
      title: 'Restore lost streak',
      summary: '',
      inputs: [],
      risk: 'low',
      state: HolloConfirmState.pending,
    );

    // A server error leaves the card open with a short line.
    final answering = store.answerConfirmation(first, confirm: true);
    expect(store.isDeciding(first), isTrue);
    await answering;
    expect(store.isDeciding(first), isFalse);
    expect(store.confirmState(card), HolloConfirmState.pending);
    expect(store.decideError(first), isNotNull);

    await store.answerConfirmation(first, confirm: true);
    expect(store.confirmState(card), HolloConfirmState.confirmed);
    expect(store.decideError(first), isNull);
    expect(
      jsonDecode(server.to('POST', '/confirmations').last.body),
      {'id': first, 'decision': 'confirm'},
    );

    // Answered already: a second tap sends nothing.
    await store.answerConfirmation(first, confirm: false);
    expect(server.to('POST', '/confirmations'), hasLength(2));

    await store.answerConfirmation(second, confirm: false);
    expect(
      jsonDecode(server.to('POST', '/confirmations').last.body),
      {'id': second, 'decision': 'cancel'},
    );
    const other = HolloConfirmation(
      id: second,
      title: 'Restore lost streak',
      summary: '',
      inputs: [],
      risk: 'low',
      state: HolloConfirmState.pending,
    );
    expect(store.confirmState(other), HolloConfirmState.unavailable);
    expect(store.decideError(second), isNull);
  });

  test('calls before start explain what to do', () async {
    final store = HolloStore();
    await expectLater(store.track('x'), throwsA(isA<StateError>()));
  });
}

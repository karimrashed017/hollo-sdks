import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollo/hollo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';

/// A server whose conversation starts with [messages].
FakeServer chatServer(List<Map<String, Object?>> messages) {
  final sent = <Map<String, Object?>>[];
  return FakeServer({
    'POST /devices': (_) =>
        reply(201, {'deviceToken': 'hdt_widget_token_value_1234'}),
    'GET /messages': (request) => reply(200, {
          'messages': request.url.queryParameters['after'] == null
              ? [...messages, ...sent]
              : sent,
          'unread': 0,
          'profile': {'name': 'Karim', 'role': 'Founder of Driftwood'},
          'push': {'permissionCard': 'off', 'notifyLine': true},
          'open': false,
        }),
    'POST /messages': (request) {
      final fields = jsonDecode(request.body) as Map<String, Object?>;
      final photos = fields['photos'];
      final created = {
        ...message(
          '${sent.length + 7}',
          'end_user',
          '${fields['body'] ?? ''}',
          kind: photos is List ? 'image' : 'text',
        ),
        if (photos is List)
          'photos': [for (final path in photos) 'https://cdn.example/$path'],
      };
      sent.add(created);
      return reply(201, {'message': created});
    },
    'POST /photos': (_) => reply(201, {
          'photo': {'path': 'p1.jpg'},
        }),
    'POST /read': (_) => reply(200, {'unread': 0}),
    'POST /links/tap': (_) => reply(200, {'ok': true}),
    'POST /confirmations': (request) {
      final fields = jsonDecode(request.body) as Map<String, Object?>;
      return reply(200, {
        'status': fields['decision'] == 'confirm' ? 'confirmed' : 'cancelled',
      });
    },
  });
}

/// Lets the first poll land and the chat rebuild.
Future<void> load(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(Hollo.debugReset);

  testWidgets('shows the conversation, the AI label and a review card',
      (tester) async {
    final server = chatServer([
      message('1', 'team', 'Hi, how can we help?'),
      message('2', 'ai', 'Restores are under Settings.'),
      message(
        '3',
        'team',
        'Enjoying Driftwood? A review would mean a lot.',
        kind: 'review_request',
        payload: {
          'appStoreId': '123456789',
          'playStorePackage': 'com.example.app',
          'cta': 'Leave a review',
        },
      ),
    ]);
    final opened = <Uri>[];
    Hollo.openUrl = (uri) async {
      opened.add(uri);
      return true;
    };
    await Hollo.start(appKey: appKey, httpClient: server.client);
    await tester.pumpWidget(const MaterialApp(home: HolloChat()));
    await load(tester);

    expect(find.text('Founder of Driftwood'), findsOneWidget);
    expect(find.text('Hi, how can we help?'), findsOneWidget);
    expect(find.text('Restores are under Settings.'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('Karim'), findsNWidgets(2), reason: 'header and label');
    expect(find.text('Leave a review'), findsOneWidget);
    // Embedded chats count as open, so replies are marked read.
    expect(server.to('POST', '/read'), isNotEmpty);
    expect(Hollo.unreadCount.value, 0);

    await tester.tap(find.text('Leave a review'));
    await tester.pump();
    // Flutter tests run as Android.
    expect(opened.single.toString(), 'market://details?id=com.example.app');

    Hollo.debugReset();
  });

  testWidgets('offer and screen link cards call the app', (tester) async {
    final server = chatServer([
      message(
        '1',
        'team',
        'Half price',
        kind: 'offer',
        payload: {
          'title': 'Half price for a year',
          'description': 'Today only',
          'cta': 'Get the offer',
          'ref': 'yearly_50',
        },
      ),
      message(
        '2',
        'team',
        'Your order is on its way.',
        kind: 'link',
        payload: {
          'linkId': 'link_1',
          'label': 'Track order',
          'url': null,
          'screen': 'order',
          'value': 'A123',
        },
      ),
    ]);
    HolloOffer? offer;
    HolloLink? link;
    Hollo.onOffer = (tapped) => offer = tapped;
    Hollo.onLink = (tapped) => link = tapped;
    await Hollo.start(appKey: appKey, httpClient: server.client);
    await tester.pumpWidget(const MaterialApp(home: HolloChat()));
    await load(tester);

    await tester.tap(find.text('Get the offer'));
    await tester.pump();
    expect(offer?.ref, 'yearly_50');
    expect(offer?.title, 'Half price for a year');

    await tester.tap(find.text('Track order'));
    await load(tester);
    expect(link?.screen, 'order');
    expect(link?.value, 'A123');
    final tap = server.to('POST', '/links/tap').single;
    expect(jsonDecode(tap.body), {'messageId': '2', 'opened': true});

    Hollo.debugReset();
  });

  testWidgets('a confirm card sends the answer, then shows it',
      (tester) async {
    const id = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
    final server = chatServer([
      message(
        '1',
        'ai',
        'Restore your streak to 41 days?',
        kind: 'action_confirm',
        payload: {
          'confirmationId': id,
          'title': 'Restore lost streak',
          'summary': 'Restore your streak to 41 days',
          'inputs': [
            {'label': 'Streak days', 'value': '41'},
          ],
          'risk': 'low',
          'status': 'pending',
          'expiresAt': '2999-01-01T00:00:00.000Z',
        },
      ),
      message(
        '2',
        'ai',
        'That one ran out of time.',
        kind: 'action_confirm',
        payload: {
          'confirmationId': '0f8fad5b-d9cb-469f-a165-70867728950e',
          'title': 'Old change',
          'status': 'pending',
          'expiresAt': '2020-01-01T00:00:00.000Z',
        },
      ),
    ]);
    await Hollo.start(appKey: appKey, httpClient: server.client);
    await tester.pumpWidget(const MaterialApp(home: HolloChat()));
    await load(tester);

    expect(find.text('Restore lost streak'), findsOneWidget);
    expect(find.text('Restore your streak to 41 days'), findsOneWidget);
    expect(find.text('Streak days: 41'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget, reason: 'one card waits');

    await tester.tap(find.text('Confirm'));
    await load(tester);
    expect(
      jsonDecode(server.to('POST', '/confirmations').single.body),
      {'id': id, 'decision': 'confirm'},
    );
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);

    Hollo.debugReset();
  });

  testWidgets('sends a message', (tester) async {
    final server = chatServer([]);
    await Hollo.start(appKey: appKey, httpClient: server.client);
    await tester.pumpWidget(const MaterialApp(home: HolloChat()));
    await load(tester);
    expect(find.text('How can we help?'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'My backup is missing');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await load(tester);

    expect(find.text('My backup is missing'), findsOneWidget);
    expect(server.to('POST', '/messages'), hasLength(1));

    Hollo.debugReset();
  });

  testWidgets('present() opens the chat, Done closes it, and a Hollo '
      'notification opens it again', (tester) async {
    final server = chatServer([]);
    await Hollo.start(appKey: appKey, httpClient: server.client);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: Hollo.navigatorKey,
        home: const Scaffold(body: Text('Home')),
      ),
    );

    unawaited(Hollo.present());
    await tester.pumpAndSettle();
    expect(find.byType(HolloChat), findsOneWidget);
    expect(find.text('Karim'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(HolloChat), findsNothing);

    expect(Hollo.handle({'from': 'elsewhere'}), isFalse);
    expect(Hollo.handle({'hollo': 'true'}), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(HolloChat), findsOneWidget);

    Hollo.debugReset();
  });

  testWidgets('an image message shows its photos and caption, and opens '
      'full screen', (tester) async {
    final server = chatServer([
      {
        ...message('1', 'end_user', 'The sync error', kind: 'image'),
        'photos': [
          'https://cdn.example/1.jpg',
          'https://cdn.example/2.jpg',
        ],
      },
    ]);
    await Hollo.start(appKey: appKey, httpClient: server.client);
    await tester.pumpWidget(const MaterialApp(home: HolloChat()));
    await load(tester);

    expect(networkImage('https://cdn.example/1.jpg'), findsOneWidget);
    expect(networkImage('https://cdn.example/2.jpg'), findsOneWidget);
    expect(find.text('The sync error'), findsOneWidget);

    await tester.tap(networkImage('https://cdn.example/2.jpg'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);

    Hollo.debugReset();
  });

  testWidgets('attaches photos, removes one and sends the other',
      (tester) async {
    final server = chatServer([]);
    final limits = <int>[];
    Hollo.pickPhotos = (limit) async {
      limits.add(limit);
      return [pixel, pixel];
    };
    await Hollo.start(appKey: appKey, httpClient: server.client);
    await tester.pumpWidget(const MaterialApp(home: HolloChat()));
    await load(tester);

    await tester.tap(find.byTooltip('Attach photos'));
    await load(tester);
    expect(limits, [5]);
    expect(find.byIcon(Icons.close), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);

    // Photos alone can be sent, with no caption.
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await load(tester);

    expect(server.to('POST', '/photos').single.bodyBytes, pixel);
    expect(jsonDecode(server.to('POST', '/messages').single.body), {
      'photos': ['p1.jpg'],
    });
    expect(find.byIcon(Icons.close), findsNothing, reason: 'strip cleared');
    expect(networkImage('https://cdn.example/p1.jpg'), findsOneWidget);

    Hollo.debugReset();
  });
}

/// A real 1×1 PNG, so the thumbnail strip can decode it.
final Uint8List pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

Finder networkImage(String url) => find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is NetworkImage &&
          (widget.image as NetworkImage).url == url,
    );

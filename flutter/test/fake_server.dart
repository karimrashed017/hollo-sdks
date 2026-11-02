import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// A fake SDK API that answers by "METHOD /path", for the client, store and
// widget tests.

const String appKey = 'app_0123456789abcdef0123456789abcdef';

typedef FakeRoute = http.Response Function(http.Request request);

class FakeServer {
  FakeServer(this.routes);

  final Map<String, FakeRoute> routes;
  final List<http.Request> calls = <http.Request>[];

  late final MockClient client = MockClient((request) async {
    calls.add(request);
    final path = request.url.path.replaceFirst('/api/v1', '');
    final route = routes['${request.method} $path'];
    if (route == null) {
      return reply(404, {
        'error': {'code': 'not_found', 'message': 'No route'},
      });
    }
    return route(request);
  });

  /// The requests made to one endpoint, oldest first.
  List<http.Request> to(String method, String path) => calls
      .where((call) => call.method == method && call.url.path.endsWith(path))
      .toList();
}

http.Response reply(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object?> message(
  String id,
  String sender,
  String body, {
  String kind = 'text',
  Map<String, Object?> payload = const <String, Object?>{},
  String? at,
}) =>
    {
      'id': id,
      'sender': sender,
      'kind': kind,
      'body': body,
      'payload': payload,
      'created_at': at ?? '2026-11-02T10:00:0$id.000000+00:00',
    };

/// Lets queued futures (fire-and-forget calls) finish in plain tests.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

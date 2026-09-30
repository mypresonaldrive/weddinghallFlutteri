import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatherhall/src/core/api.dart';

/// Exercises ApiClient against a real localhost server: cookie jar, CSRF
/// header injection, JSON parsing and error mapping.
void main() {
  late HttpServer server;
  late String baseUrl;
  List<Cookie> receivedCookies = <Cookie>[];
  Map<String, String> lastHeaders = <String, String>{};
  String? lastPath;
  dynamic lastBody;

  setUp(() async {
    receivedCookies = <Cookie>[];
    lastHeaders = <String, String>{};
    lastPath = null;
    lastBody = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      lastPath = request.uri.path;
      lastHeaders = <String, String>{
        for (final name in request.headers.names)
          name.toLowerCase(): request.headers.value(name) ?? '',
      };
      final raw = await utf8.decoder.bind(request).join();
      lastBody = raw.isEmpty ? null : jsonDecode(raw);

      // Mimic the real server: issue a CSRF cookie on any API hit.
      request.response.cookies.add(Cookie('gh_csrf', 'c' * 48));
      final needsCsrf = request.method == 'POST' || request.method == 'PUT';
      final csrfOk = !needsCsrf ||
          request.headers.value('x-csrf-token') == ('c' * 48);
      if (!csrfOk) {
        request.response.statusCode = 403;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': 'CSRF token invalid'
        }));
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/api/data':
          request.response.write(jsonEncode({
            'records': {
              'halls': <dynamic>[{'id': 'h1', 'name': 'Ballroom'}],
              'bookings': <dynamic>[],
            },
            'platform': null,
          }));
        case '/api/bookings':
          request.response.write(jsonEncode({'success': true}));
        case '/api/missing':
          request.response.statusCode = 404;
          request.response.write(
              jsonEncode({'error': 'Resource not found.'}));
        case '/api/locked':
          request.response.statusCode = 402;
          request.response.write(jsonEncode({'error': 'Upgrade required'}));
        case '/api/list':
          request.response.write(jsonEncode(<dynamic>[]));
        default:
          request.response.write(jsonEncode({'success': true}));
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  ApiClient newClient() => ApiClient(baseUrl: baseUrl);

  test('first GET absorbs Set-Cookie and resends it on later requests', () async {
    final client = newClient();
    await client.getMap('/api/data');
    await client.getMap('/api/data');
    expect(receivedCookies.map((c) => c.name), contains('gh_csrf'));
    expect(lastHeaders['cookie'], contains('gh_csrf=c'));
  });

  test('POST attaches x-csrf-token from the cookie jar', () async {
    final client = newClient();
    await client.getMap('/api/data'); // seeds the jar
    await client.post('/api/bookings', {'a': 1});
    expect(lastHeaders['x-csrf-token'], 'c' * 48);
    expect(lastBody, {'a': 1});
  });

  test('getMap and getList shapes', () async {
    final client = newClient();
    final object = await client.getMap('/api/data');
    expect(object['records'], isA<Map<String, dynamic>>());
    final list = await client.getList('/api/list');
    expect(list, isEmpty);
    await expectLater(client.getList('/api/data'), throwsA(isA<ApiException>()));
  });

  test('error mapping: 404 → ApiException with status; JSON error message', () async {
    final client = newClient();
    await expectLater(
      client.get('/api/missing'),
      throwsA(isA<ApiException>()
          .having((e) => e.status, 'status', 404)
          .having((e) => e.message, 'message', 'Resource not found.')),
    );
  });

  test('402 body from /api/locked maps to ApiException(402)', () async {
    final client = newClient();
    try {
      await client.getMap('/api/locked');
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.status, 402);
      expect(e.message, 'Upgrade required');
    }
  });

  test('server unreachable maps to friendly ApiException', () async {
    final client = ApiClient(baseUrl: 'http://127.0.0.1:1');
    try {
      await client.getMap('/api/data');
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.status, isNull);
      expect(e.message, contains('Cannot reach the server'));
    }
  });
}

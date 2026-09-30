import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Error raised for any failed or unreachable API call, with a user-facing message.
class ApiException implements Exception {
  ApiException(this.message, {this.status});

  final String message;
  final int? status;

  bool get isAuth => status == 401;

  @override
  String toString() => message;
}

/// Minimal cookie-aware JSON HTTP client for the Gatherhall Express API.
///
/// The production server authenticates with HTTP-only cookies and requires a
/// double-submit CSRF token (`gh_csrf` cookie echoed as `x-csrf-token`) on all
/// mutating requests. No `Origin` header is sent, which the server allows.
class ApiClient {
  ApiClient({this.baseUrl = 'http://localhost:3000'});

  String baseUrl;
  final Map<String, String> _cookies = <String, String>{};
  String? csrfToken;

  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _requestTimeout = Duration(seconds: 45);

  Map<String, String> cookieSnapshot() => Map<String, String>.from(_cookies);

  void restore({required Map<String, String> cookies}) {
    _cookies
      ..clear()
      ..addAll(cookies);
    csrfToken = _cookies['gh_csrf'];
  }

  void reset() {
    _cookies.clear();
    csrfToken = null;
  }

  Uri _uri(String path) {
    final normalizedBase =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$normalizedBase$path');
  }

  void _absorbCookies(HttpHeaders headers) {
    final raw = headers[HttpHeaders.setCookieHeader];
    if (raw == null) return;
    for (final header in raw) {
      final pair = header.split(';').first;
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (value.isEmpty) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
      if (name == 'gh_csrf') csrfToken = value;
    }
  }

  /// Sends a request and returns decoded JSON (a `Map` or a `List`).
  Future<dynamic> request(String method, String path, {Object? body}) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final future = _send(client, method, path, body);
      return await future.timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException('The server took too long to respond. Please try again.');
    } on SocketException {
      throw ApiException(
          'Cannot reach the server at $baseUrl. Check the server address in Settings.');
    } on HandshakeException {
      throw ApiException('Secure connection to $baseUrl failed.');
    } on HttpException catch (e) {
      throw ApiException('Server connection failed: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<dynamic> _send(
      HttpClient client, String method, String path, Object? body) async {
    final request = await client.openUrl(method, _uri(path));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    if (_cookies.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader,
          _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
    }
    final mutating = method != 'GET' && method != 'HEAD';
    if (mutating && csrfToken != null) {
      request.headers.set('x-csrf-token', csrfToken!);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    _absorbCookies(response.headers);
    final text = await response.transform(utf8.decoder).join();
    dynamic decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
    }
    if (response.statusCode >= 400) {
      String message;
      if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      } else if (response.statusCode == 401) {
        message = 'Please sign in to continue.';
      } else if (response.statusCode == 429) {
        message = 'Too many attempts. Please try again later.';
      } else {
        message = 'Request failed (HTTP ${response.statusCode}).';
      }
      throw ApiException(message, status: response.statusCode);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> getMap(String path) async {
    final data = await request('GET', path);
    if (data is Map<String, dynamic>) return data;
    throw ApiException('The server returned an unexpected response.');
  }

  Future<List<dynamic>> getList(String path) async {
    final data = await request('GET', path);
    if (data is List) return data;
    throw ApiException('The server returned an unexpected response.');
  }

  Future<Map<String, dynamic>> post(String path, [Object? body]) async {
    final data = await request('POST', path, body: body ?? <String, dynamic>{});
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> put(String path, Object? body) async {
    final data = await request('PUT', path, body: body ?? <String, dynamic>{});
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final data = await request('DELETE', path);
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{'ok': true};
  }
}

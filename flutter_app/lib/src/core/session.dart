import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'storage.dart';

enum BootPhase { starting, signedOut, needsOnboarding, workspace, unreachable }

/// Owns authentication, the current user and the server configuration.
class SessionStore extends ChangeNotifier {
  SessionStore(this._prefs);

  final KeyValueStore _prefs;
  late ApiClient api;
  String baseUrl = '';
  AppConfig config = AppConfig(mode: 'demo');
  CurrentUser? user;
  BootPhase phase = BootPhase.starting;
  String? bootError;
  bool disposed = false;

  static const String defaultPath = '/api/config';

  Future<void> init() async {
    final saved = _prefs.get('baseUrl');
    baseUrl = (saved is String && saved.isNotEmpty)
        ? saved
        : defaultBaseUrl();
    api = ApiClient(baseUrl: baseUrl);
    final cookies = _prefs.get('cookies');
    if (cookies is Map) {
      api.restore(cookies: cookies.map((k, v) => MapEntry(k.toString(), v.toString())));
    }
    await checkServer();
  }

  static String defaultBaseUrl() => 'http://localhost:3000';

  Future<void> _persistCookies() async {
    await _prefs.set('cookies', api.cookieSnapshot());
  }

  Future<void> setBaseUrl(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    baseUrl = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    api = ApiClient(baseUrl: baseUrl);
    api.reset();
    user = null;
    await _prefs.set('baseUrl', baseUrl);
    await _prefs.set('cookies', <String, dynamic>{});
    notifyListeners();
    await checkServer();
  }

  void _emit() {
    if (!disposed) notifyListeners();
  }

  /// Fetches `/api/config` and restores the session from stored cookies.
  Future<void> checkServer() async {
    phase = BootPhase.starting;
    bootError = null;
    _emit();
    try {
      config = AppConfig.fromJson(await api.getMap(defaultPath));
      await _persistCookies();
      await _refreshUser();
    } on ApiException catch (e) {
      if (e.status == null) {
        phase = BootPhase.unreachable;
        bootError = e.message;
      } else {
        phase = BootPhase.signedOut;
      }
      user = null;
      _emit();
    } catch (e) {
      phase = BootPhase.unreachable;
      bootError = e.toString();
      _emit();
    }
  }

  Future<void> _refreshUser() async {
    try {
      final json = await api.getMap('/api/auth/me');
      user = CurrentUser.fromJson(json);
      await _persistCookies();
      if (user!.needsOnboarding) {
        phase = BootPhase.needsOnboarding;
      } else if (user!.inWorkspace || user!.platformAdmin) {
        phase = BootPhase.workspace;
      } else {
        phase = BootPhase.signedOut;
      }
    } on ApiException catch (e) {
      user = null;
      phase = e.status == 401 ? BootPhase.signedOut : BootPhase.unreachable;
      if (phase == BootPhase.unreachable) bootError = e.message;
    }
    _emit();
  }

  /// Re-reads `/api/auth/me` after profile/membership changes.
  Future<void> refreshMe() => _refreshUser();

  Future<void> login(String email, String password) async {
    await api.post('/api/auth/login', <String, dynamic>{
      'email': email.trim(),
      'password': password,
    });
    await _persistCookies();
    await _refreshUser();
    if (phase == BootPhase.signedOut) {
      throw ApiException('Unable to sign in. Check your email, password and verification.',
          status: 401);
    }
  }

  Future<String> registerDemo({
    required String name,
    required String email,
    required String password,
    required String organization,
  }) async {
    await api.post('/api/auth/register', <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'organization': organization.trim(),
    });
    await login(email, password);
    return 'Workspace created. Welcome to Gatherhall!';
  }

  Future<String> registerSaas({
    required String name,
    required String email,
    required String password,
  }) async {
    await api.post('/api/auth/register', <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
    });
    return 'Check your email to verify your account before signing in.';
  }

  Future<String> forgotPassword(String email) async {
    final response =
        await api.post('/api/auth/forgot', <String, dynamic>{'email': email.trim()});
    return (response['message'] as String?) ??
        'If this account is eligible, a password reset email has been sent.';
  }

  Future<void> logout() async {
    try {
      await api.post('/api/auth/logout');
    } catch (_) {
      // Session may already be invalid.
    }
    api.reset();
    user = null;
    phase = BootPhase.signedOut;
    await _prefs.set('cookies', <String, dynamic>{});
    _emit();
  }

  Future<void> updateProfile({required String name, String? organization}) async {
    final body = <String, dynamic>{'name': name.trim()};
    if (organization != null && organization.trim().isNotEmpty) {
      body['organization'] = organization.trim();
    }
    final json = await api.put('/api/settings/profile', body);
    user = CurrentUser.fromJson(json);
    _emit();
  }

  Future<void> changePassword(String password) async {
    await api.post('/api/auth/password', <String, dynamic>{'password': password});
  }

  Future<List<Map<String, dynamic>>> invitations() async {
    final list = await api.getList('/api/invitations');
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> acceptInvitation(String invitationId) async {
    await api.post('/api/invitations/accept', <String, dynamic>{'invitationId': invitationId});
    await _refreshUser();
  }

  Future<List<Map<String, dynamic>>> mfaFactors() async {
    final list = await api.getList('/api/auth/mfa');
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> mfaEnroll() =>
      api.post('/api/auth/mfa/enroll', <String, dynamic>{});

  Future<void> mfaVerify({required String factorId, required String code}) async {
    await api.post('/api/auth/mfa/verify', <String, dynamic>{
      'factorId': factorId,
      'code': code,
    });
    await _refreshUser();
  }

  Future<void> acceptOrganization({
    required String name,
    required String phone,
    required String city,
    required String planId,
    required String interval,
  }) async {
    await api.post('/api/onboarding', <String, dynamic>{
      'name': name.trim(),
      'phone': phone.trim(),
      'city': city.trim(),
      'planId': planId,
      'interval': interval,
    });
    await _refreshUser();
  }
}

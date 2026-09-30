// End-to-end smoke test for the Gatherhall demo server, exercised through the
// same ApiClient the Flutter app uses. Run with the demo server on port 3000:
//
//   node server.js &            # APP_MODE defaults to demo outside production
//   dart run tool/e2e_demo.dart
//
// Exits non-zero on the first failure.

import 'dart:io';

import 'package:gatherhall/src/core/api.dart';

const String baseUrl = String.fromEnvironment('E2E_URL',
    defaultValue: 'http://127.0.0.1:3000');

final ApiClient api = ApiClient(baseUrl: baseUrl);

var _step = 0;

void ok(String message) {
  _step += 1;
  stdout.writeln('✓ [$_step] $message');
}

void fail(String message) {
  stderr.writeln('✗ [$_step] $message');
  exit(1);
}

Future<T> expectApi<T>(Future<T> Function() run, String what) async {
  try {
    return await run();
  } on ApiException catch (e) {
    fail('$what → ApiException(${e.status}): ${e.message}');
    rethrow;
  }
}

Future<void> main() async {
  // 1. Server config reachable and in demo mode.
  final config = await expectApi(() => api.getMap('/api/config'), 'GET /api/config');
  if (config['mode'] != 'demo') {
    fail('expected demo mode, got ${config['mode']}');
  }
  ok('demo server reachable at $baseUrl');

  // Public discovery works with no session: halls, detail, policy, enquiry.
  final publicHalls = await expectApi(
      () => api.getMap('/api/public/halls'), 'GET /api/public/halls');
  final publicList = (publicHalls['halls'] as List<dynamic>? ?? <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .toList();
  if (publicList.isEmpty) fail('expected public halls without a session');
  final publicCities = (publicHalls['cities'] as List<dynamic>? ?? <dynamic>[])
      .map((dynamic c) => c.toString())
      .toList();
  ok('public halls listed without login: ${publicList.length} halls '
      '(areas: ${publicCities.join(', ')})');

  final detailId = publicList.first['id'];
  final hallDetail = await expectApi(
      () => api.getMap('/api/public/halls/$detailId'),
      'GET /api/public/halls/:id');
  if (hallDetail['hall'] == null) fail('public hall detail missing');
  final detailAddons = (hallDetail['addons'] as List<dynamic>? ?? <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .length;
  ok('public hall detail loads ($detailAddons services on offer)');

  final content = await expectApi(
      () => api.getList('/api/public/content?locale=en'),
      'GET /api/public/content');
  final policies = content
      .whereType<Map<String, dynamic>>()
      .where((entry) => entry['slug'] == 'privacy')
      .toList();
  if (policies.isEmpty) fail('expected published privacy policy in content');
  ok('privacy policy published for enquiry consent');

  await expectApi(
      () => api.post('/api/public/enquiries', <String, dynamic>{
            'name': 'E2E Visitor',
            'email': 'visitor@example.test',
            'organization': 'E2E walkthrough',
            'message': 'Is the ballroom free for a December wedding?',
            'locale': 'en',
            'consent': true,
            'website': '',
            'policyId': policies.first['id'],
            'policyRevision': policies.first['published_revision'],
          }),
      'POST /api/public/enquiries');
  ok('hall enquiry submitted without login');

  // 2. Wrong password maps to ApiException with HTTP status 401.
  try {
    await api.post('/api/auth/login', {
      'email': 'owner@gatherhall.demo',
      'password': 'DefinitelyWrong1!',
    });
    fail('wrong password should throw');
  } on ApiException catch (e) {
    if (e.status != 401) fail('expected 401, got ${e.status}');
    ok('bad credentials rejected with 401: ${e.message}');
  }

  // 3. Owner login succeeds and issues cookies.
  await expectApi(
      () => api.post('/api/auth/login', {
            'email': 'owner@gatherhall.demo',
            'password': 'Welcome123!',
          }),
      'owner login');
  if (!api.cookieSnapshot().containsKey('session')) {
    fail('session cookie missing after login');
  }
  ok('owner signed in (session cookie present)');

  // 4. Seed data loads.
  final data = await expectApi(() => api.getMap('/api/data'), 'GET /api/data');
  final halls = (data['halls'] as List<dynamic>? ?? <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .toList();
  final plans = (data['plans'] as List<dynamic>? ?? <dynamic>[])
      .whereType<Map<String, dynamic>>()
      .toList();
  if (halls.isEmpty) fail('expected seeded halls');
  if (plans.isEmpty) fail('expected seeded plans');
  ok('workspace data: ${halls.length} halls, ${plans.length} plans');

  final hall = halls.firstWhere(
      (h) => h['status'] != 'Maintenance',
      orElse: () => halls.first);
  final plan = plans.firstWhere((p) => p['status'] == 'Active',
      orElse: () => plans.first);

  // 5. Create a client record (directory-only, no provisioned login).
  final client = await expectApi(
      () => api.post('/api/clients', {
            'name': 'E2E Test Client',
            'email': 'e2e-client@wavefarm.test',
            'phone': '+91 90000 00001',
            'notes': 'Created by flutter_app/tool/e2e_demo.dart',
            'status': 'Active',
          }),
      'POST /api/clients');
  final clientId = client['id']?.toString() ?? '';
  if (clientId.isEmpty) fail('client id missing');
  ok('client created ($clientId)');

  final capacity = (hall['capacity'] as num?)?.toInt() ?? 200;
  final guests = capacity < 150 ? capacity : 150;
  final date = '2026-11-20'; // far from seed data → no overlap

  // 6. Create a plan-backed booking (server recomputes the quote).
  final booking = await expectApi(
      () => api.post('/api/bookings', {
            'name': 'E2E Celebration',
            'clientId': clientId,
            'hallId': hall['id'],
            'planId': plan['id'],
            'date': date,
            'time': '18:00',
            'durationMode': 'evening',
            'guests': guests,
            'type': 'Wedding',
            'status': 'Confirmed',
            'plateType': 'Vegetarian',
            'notes': 'Created by flutter_app/tool/e2e_demo.dart',
          }),
      'POST /api/bookings');
  final bookingId = booking['id']?.toString() ?? '';
  if (bookingId.isEmpty) fail('booking id missing');
  final total = (booking['total'] as num?) ?? 0;
  if (total <= 0) fail('booking total not computed (got $total)');
  ok('booking created ($bookingId) total=$total plan=${plan['name']}');

  // 7. Availability reflects the new booking for that hall/date.
  final availability = await expectApi(
      () => api.getMap('/api/availability?date=$date&durationMode=evening'),
      'GET /api/availability');
  final availabilityHalls =
      (availability['halls'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
  final entry = availabilityHalls
      .where((h) => h['id'] == hall['id'])
      .cast<Map<String, dynamic>?>()
      .firstWhere((h) => h != null, orElse: () => null);
  if (entry == null) fail('hall missing from availability response');
  if (entry!['available'] != false) {
    fail('expected hall to be unavailable after booking');
  }
  ok('availability marks ${hall['name']} as reserved');

  // 8. Record a payment within the balance.
  final amount = total ~/ 2 > 0 ? total ~/ 2 : 1;
  final payment = await expectApi(
      () => api.post('/api/payments', {
            'bookingId': bookingId,
            'amount': amount,
            'date': date,
            'method': 'UPI',
            'reference': 'e2e-test',
          }),
      'POST /api/payments');
  final paymentId = payment['id']?.toString() ?? '';
  if (paymentId.isEmpty) fail('payment id missing');
  ok('payment recorded ($paymentId, ₹$amount)');

  // 9. Payment beyond balance is rejected.
  try {
    await api.post('/api/payments', {
      'bookingId': bookingId,
      'amount': total * 2,
      'date': date,
      'method': 'Cash',
    });
    fail('over-balance payment should be rejected');
  } on ApiException catch (e) {
    ok('over-balance payment rejected: ${e.message}');
  }

  // 10. Clean up in dependency order.
  await expectApi(() => api.delete('/api/payments/$paymentId'),
      'DELETE payment');
  await expectApi(
      () => api.delete('/api/bookings/$bookingId'), 'DELETE booking');
  await expectApi(() => api.delete('/api/clients/$clientId'), 'DELETE client');
  ok('cleanup complete');

  // 11. Logout drops the session.
  await expectApi(() => api.post('/api/auth/logout'), 'logout');
  api.reset();
  try {
    await api.getMap('/api/data');
    fail('data should require authentication after logout');
  } on ApiException catch (e) {
    if (e.status != 401) fail('expected 401 after logout, got ${e.status}');
    ok('session invalidated after logout (401)');
  }

  stdout.writeln('');
  stdout.writeln('E2E passed: $_step steps against $baseUrl');
  exit(0);
}

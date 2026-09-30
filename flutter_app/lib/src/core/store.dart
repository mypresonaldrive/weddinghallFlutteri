import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'session.dart';

/// Loads and mutates the tenant workspace records.
class WorkspaceStore extends ChangeNotifier {
  WorkspaceStore(this._session);

  final SessionStore _session;
  List<RecordItem> halls = <RecordItem>[];
  List<RecordItem> bookings = <RecordItem>[];
  List<RecordItem> clients = <RecordItem>[];
  List<RecordItem> payments = <RecordItem>[];
  List<RecordItem> staff = <RecordItem>[];
  List<RecordItem> plans = <RecordItem>[];
  List<RecordItem> addons = <RecordItem>[];
  bool loading = false;
  String? error;
  bool disposed = false;

  ApiClient get _api => _session.api;

  List<RecordItem> listFor(String kind) {
    switch (kind) {
      case 'halls':
        return halls;
      case 'bookings':
        return bookings;
      case 'clients':
        return clients;
      case 'payments':
        return payments;
      case 'staff':
        return staff;
      case 'plans':
        return plans;
      case 'addons':
        return addons;
      default:
        return <RecordItem>[];
    }
  }

  void _setList(String kind, List<RecordItem> items) {
    switch (kind) {
      case 'halls':
        halls = items;
        break;
      case 'bookings':
        bookings = items;
        break;
      case 'clients':
        clients = items;
        break;
      case 'payments':
        payments = items;
        break;
      case 'staff':
        staff = items;
        break;
      case 'plans':
        plans = items;
        break;
      case 'addons':
        addons = items;
        break;
    }
  }

  void _emit() {
    if (!disposed) notifyListeners();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      error = null;
      _emit();
    }
    try {
      final json = await _api.getMap('/api/data');
      halls = _parse('halls', json['halls']);
      bookings = _parse('bookings', json['bookings']);
      clients = _parse('clients', json['clients']);
      payments = _parse('payments', json['payments']);
      staff = _parse('staff', json['staff']);
      plans = _parse('plans', json['plans']);
      addons = _parse('addons', json['addons']);
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      _emit();
    }
  }

  List<RecordItem> _parse(String kind, dynamic raw) {
    if (raw is! List) return <RecordItem>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((m) => RecordItem(kind, m))
        .toList();
  }

  String _path(String kind) => '/api/$kind';

  Future<RecordItem> create(String kind, Map<String, dynamic> body) async {
    final json = await _api.post(_path(kind), body);
    final item = RecordItem(kind, json);
    if (item.id.isNotEmpty) {
      final list = List<RecordItem>.from(listFor(kind))..insert(0, item);
      _setList(kind, list);
      _emit();
    } else {
      await load(silent: true);
    }
    return item;
  }

  Future<RecordItem> update(String kind, String id, Map<String, dynamic> body) async {
    // Optimistic concurrency: stamp the last known version so the server can
    // reject a stale overwrite. Callers that already include 'version' win.
    RecordItem? current;
    for (final r in listFor(kind)) {
      if (r.id == id) {
        current = r;
        break;
      }
    }
    if (body['version'] == null &&
        current != null &&
        current.data['version'] != null) {
      body = Map<String, dynamic>.from(body)
        ..['version'] = current.data['version'];
    }
    final json = await _api.put('$_path(kind)/$id', body);
    json['id'] = id;
    final list = List<RecordItem>.from(listFor(kind));
    final index = list.indexWhere((r) => r.id == id);
    final item = RecordItem(kind, json);
    if (index >= 0) {
      list[index] = item;
    } else {
      list.insert(0, item);
    }
    _setList(kind, list);
    _emit();
    return item;
  }

  Future<void> remove(String kind, String id) async {
    await _api.delete('$_path(kind)/$id');
    final list = List<RecordItem>.from(listFor(kind))..removeWhere((r) => r.id == id);
    _setList(kind, list);
    _emit();
    // The server may cascade related records (e.g. booking payments).
    await load(silent: true);
  }

  Future<AvailabilityResult> availability(Map<String, String> query) async {
    final params = <String, String>{...query};
    final uri = Uri(path: '/api/availability', queryParameters: params);
    final json = await _api.getMap('$uri');
    return AvailabilityResult.fromJson(json);
  }

  Future<void> inviteTeamMember(String recordId) async {
    await _api.post('/api/team/invite', <String, dynamic>{'recordId': recordId});
  }

  Future<Map<String, dynamic>> billing() => _api.getMap('/api/billing');

  Future<List<RecordItem>> recordsOf(String kind) async {
    await load(silent: true);
    return listFor(kind);
  }

  RecordItem? byId(String kind, String id) {
    for (final item in listFor(kind)) {
      if (item.id == id) return item;
    }
    return null;
  }
}

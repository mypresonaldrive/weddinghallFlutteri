import 'dart:convert';
import 'dart:io';

import 'paths.dart';

/// Tiny JSON file persistence for session cookies, server URL and appearance.
class KeyValueStore {
  KeyValueStore(this._file);

  final File _file;
  Map<String, dynamic> _data = <String, dynamic>{};

  static Future<KeyValueStore> open() async {
    final dir = await appStateDir();
    final store = KeyValueStore(File('${dir.path}${Platform.pathSeparator}state.json'));
    await store._load();
    return store;
  }

  Future<void> _load() async {
    try {
      if (await _file.exists()) {
        final text = await _file.readAsString();
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          _data = decoded;
        }
      }
    } catch (_) {
      _data = <String, dynamic>{};
    }
  }

  dynamic get(String key) => _data[key];

  Future<void> set(String key, Object? value) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    await _flush();
  }

  Future<void> _flush() async {
    try {
      await _file.writeAsString(jsonEncode(_data), flush: true);
    } catch (_) {
      // Persistence is best-effort; in-memory state keeps working.
    }
  }
}

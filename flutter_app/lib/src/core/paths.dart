import 'dart:io';

/// Resolves a per-user directory for lightweight app state without plugins.
///
/// Desktop platforms use their conventional config directories. On mobile,
/// Flutter provides a writable temp directory via TMPDIR which the engine
/// points at the application sandbox; state there survives normal restarts
/// and is cleared with the app's cache.
Future<Directory> appStateDir() async {
  Directory base;
  if (Platform.isAndroid || Platform.isIOS) {
    base = Directory.systemTemp;
  } else {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      base = Directory(
          '${appData ?? '$home\\AppData\\Roaming'}${Platform.pathSeparator}Gatherhall');
    } else if (Platform.isMacOS) {
      base = Directory(
          '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}Gatherhall');
    } else {
      final xdg = Platform.environment['XDG_DATA_HOME'];
      base = Directory('${xdg ?? '$home/.local/share'}${Platform.pathSeparator}gatherhall');
    }
  }
  if (!await base.exists()) {
    await base.create(recursive: true);
  }
  return base;
}

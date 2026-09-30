import 'package:flutter/material.dart';

import 'storage.dart';

class AppearanceStore extends ChangeNotifier {
  AppearanceStore(this._prefs);

  final KeyValueStore _prefs;
  String preset = 'periwinkle';
  ThemeMode mode = ThemeMode.system;
  bool disposed = false;

  static const Map<String, Color> presets = <String, Color>{
    'periwinkle': Color(0xFF5C5C99),
    'emerald': Color(0xFF0E7C5A),
    'ocean': Color(0xFF1565C0),
    'rose': Color(0xFFAD1457),
  };

  static const Map<String, String> presetNames = <String, String>{
    'periwinkle': 'Periwinkle',
    'emerald': 'Emerald',
    'ocean': 'Ocean Blue',
    'rose': 'Rose',
  };

  Future<void> load() async {
    final savedPreset = _prefs.get('themePreset');
    if (savedPreset is String && presets.containsKey(savedPreset)) {
      preset = savedPreset;
    }
    final savedMode = _prefs.get('themeMode');
    if (savedMode is String) {
      mode = ThemeMode.values.firstWhere(
        (m) => m.name == savedMode,
        orElse: () => ThemeMode.system,
      );
    }
    _emit();
  }

  Future<void> setPreset(String value) async {
    if (!presets.containsKey(value)) return;
    preset = value;
    await _prefs.set('themePreset', value);
    _emit();
  }

  Future<void> setMode(ThemeMode value) async {
    mode = value;
    await _prefs.set('themeMode', value.name);
    _emit();
  }

  void _emit() {
    if (!disposed) notifyListeners();
  }

  Color get seedColor => presets[preset] ?? presets['periwinkle']!;

  ThemeData light() => _build(Brightness.light);

  ThemeData dark() => _build(Brightness.dark);

  ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: brightness == Brightness.light
            ? const Color(0xFFB9B9D1)
            : const Color(0xFF4A4A6A),
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F7FC)
          : const Color(0xFF12121A),
      appBarTheme: AppBarTheme(
        backgroundColor: brightness == Brightness.light ? Colors.white : const Color(0xFF1A1A24),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: brightness == Brightness.light ? Colors.white : const Color(0xFF1D1D28),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: brightness == Brightness.light
                ? const Color(0xFFE6E6F0)
                : const Color(0xFF2C2C3A),
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light ? Colors.white : const Color(0xFF22222E),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: brightness == Brightness.light ? Colors.white : const Color(0xFF16161F),
        indicatorColor: scheme.primaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: brightness == Brightness.light ? Colors.white : const Color(0xFF16161F),
        indicatorColor: scheme.primaryContainer,
      ),
      dividerTheme: DividerThemeData(
        color: brightness == Brightness.light
            ? const Color(0xFFE6E6F0)
            : const Color(0xFF2C2C3A),
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        iconColor: scheme.onSurfaceVariant,
      ),
    );
  }
}

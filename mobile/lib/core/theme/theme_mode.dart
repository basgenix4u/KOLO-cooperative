import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The member's theme choice, persisted on the device.
///
/// Defaults to [ThemeMode.system] rather than light: a group member checking
/// their balance at night should get the dark screen their phone is already
/// showing everywhere else. An explicit choice always wins over the system
/// setting and is remembered across launches.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.system) {
    _load();
  }

  static const _key = 'kolo.theme_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      if (stored != null) state = _fromName(stored);
    } catch (_) {
      // A preference that cannot be read is not worth failing a launch over.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }

  static ThemeMode _fromName(String name) => switch (name) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) => ThemeModeController());

/// A three-way choice, because "follow my phone" is a real preference and a
/// two-state switch silently overrides it.
String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'Match my phone',
      ThemeMode.light => 'Always light',
      ThemeMode.dark => 'Always dark',
    };

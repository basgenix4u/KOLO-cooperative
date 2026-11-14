import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The member's theme choice, persisted on the device.
///
/// Defaults to [ThemeMode.system] rather than light: a group member checking
/// their balance at night should get the dark screen their phone is already
/// showing everywhere else. An explicit choice always wins over the system
/// setting and is remembered across launches.
///
/// This is a [Notifier] rather than a `StateNotifier`. `StateNotifier` was
/// deprecated in Riverpod 2 and removed from the default Riverpod 3 surface
/// (still reachable through `package:flutter_riverpod/legacy.dart`, but there is
/// no reason to reach for a deprecated type in new code). `Notifier` is the
/// supported shape in both 2.x and 3.x, which is why this file compiles on
/// either without a conditional import.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'kolo.theme_mode';

  @override
  ThemeMode build() {
    // Loading is deliberately fire-and-forget: the first frame uses the system
    // theme, and the stored preference is applied as soon as it is read. A
    // preference that cannot be read is never worth blocking a launch over.
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      if (stored != null) state = _fromName(stored);
    } catch (_) {
      // Keep the system default.
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

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// A three-way choice, because "follow my phone" is a real preference and a
/// two-state switch silently overrides it.
String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'Match my phone',
      ThemeMode.light => 'Always light',
      ThemeMode.dark => 'Always dark',
    };

/// What tapping the appearance control will do next.
///
/// Distinct from [themeModeLabel], which describes the mode that is currently
/// on. On a button, "Always light" reads as a toggle already switched on; the
/// button should say where it takes you.
String themeModeNextLabel(ThemeMode current) => switch (current) {
      ThemeMode.system => 'Match my phone',
      ThemeMode.light => 'Switch to dark',
      ThemeMode.dark => 'Switch to light',
    };

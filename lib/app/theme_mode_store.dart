import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeStore {
  static const _key = 'app.themeMode';

  Future<ThemeMode> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedName = preferences.getString(_key);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == savedName,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> save(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, mode.name);
  }
}

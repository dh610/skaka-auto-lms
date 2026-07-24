import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/app/theme_mode_store.dart';

void main() {
  test('fresh install uses light theme by default', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await ThemeModeStore().load(), ThemeMode.light);
  });

  test('saved theme still takes precedence over the default', () async {
    SharedPreferences.setMockInitialValues({'app.themeMode': 'dark'});

    expect(await ThemeModeStore().load(), ThemeMode.dark);
  });
}

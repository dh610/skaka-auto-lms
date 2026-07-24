import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/attendance_schedule.dart';
import '../domain/alarm_settings.dart';

class ScheduleStore {
  static const _schedulesKey = 'attendance.schedules';
  static const _lastAlarmSettingsKey = 'attendance.lastAlarmSettings';

  Future<List<AttendanceSchedule>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_schedulesKey);
    if (encoded == null) return [];
    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      return values
          .map(
            (value) =>
                AttendanceSchedule.fromJson(value as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<AttendanceSchedule> schedules) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _schedulesKey,
      jsonEncode(schedules.map((schedule) => schedule.toJson()).toList()),
    );
  }

  Future<AlarmSettings> loadLastAlarmSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_lastAlarmSettingsKey);
    if (encoded == null) return const AlarmSettings();
    try {
      return AlarmSettings.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AlarmSettings();
    }
  }

  Future<void> saveLastAlarmSettings(AlarmSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _lastAlarmSettingsKey,
      jsonEncode(settings.toJson()),
    );
  }
}

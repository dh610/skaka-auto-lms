import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/attendance_schedule.dart';
import '../domain/alarm_settings.dart';

class ScheduleStore {
  const ScheduleStore() : _seedDefaultSchedules = false;

  const ScheduleStore.withDefaultSchedules() : _seedDefaultSchedules = true;

  static const _schedulesKey = 'attendance.schedules';
  static const _lastAlarmSettingsKey = 'attendance.lastAlarmSettings';
  static const _defaultSchedules = [
    AttendanceSchedule(
      id: 'default-weekday-check-in',
      action: AttendanceAction.checkIn,
      hour: 9,
      minute: 5,
      weekdays: {1, 2, 3, 4, 5},
      enabled: true,
      excludePublicHolidays: true,
      alarmSettings: AlarmSettings(volumePercent: 0),
    ),
    AttendanceSchedule(
      id: 'default-weekday-check-out',
      action: AttendanceAction.checkOut,
      hour: 17,
      minute: 50,
      weekdays: {1, 2, 3, 4, 5},
      enabled: true,
      excludePublicHolidays: true,
      alarmSettings: AlarmSettings(volumePercent: 0),
    ),
  ];

  final bool _seedDefaultSchedules;

  Future<List<AttendanceSchedule>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_schedulesKey);
    if (encoded == null) {
      if (!_seedDefaultSchedules) return [];
      await preferences.setString(
        _schedulesKey,
        jsonEncode(
          _defaultSchedules.map((schedule) => schedule.toJson()).toList(),
        ),
      );
      return List.of(_defaultSchedules);
    }
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

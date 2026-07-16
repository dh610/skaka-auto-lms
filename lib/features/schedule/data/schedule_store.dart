import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/attendance_schedule.dart';

class ScheduleStore {
  static const _schedulesKey = 'attendance.schedules';

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
}

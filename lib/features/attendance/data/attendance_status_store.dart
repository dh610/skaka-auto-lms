import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/daily_attendance_status.dart';

class AttendanceStatusStore {
  static const storageKey = 'attendance.todayStatus';
  static const _allowedKeys = {
    'date',
    'fetchedAt',
    'checkInTime',
    'checkOutTime',
    'earlyLeaveTime',
    'returnTime',
  };

  Future<DailyAttendanceStatus> loadFor(DateTime koreaDate) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(storageKey);
    if (encoded == null) return DailyAttendanceStatus.unqueried(koreaDate);

    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      if (!_allowedKeys.containsAll(json.keys)) throw const FormatException();

      final date = json['date'];
      if (date is! String || date != _formatDate(koreaDate)) {
        await preferences.remove(storageKey);
        return DailyAttendanceStatus.unqueried(koreaDate);
      }
      final fetchedAt = json['fetchedAt'];
      if (fetchedAt is! String) throw const FormatException();

      return DailyAttendanceStatus.queried(
        koreaDate: koreaDate,
        fetchedAt: DateTime.parse(fetchedAt),
        checkInTime: _nullableString(json, 'checkInTime'),
        checkOutTime: _nullableString(json, 'checkOutTime'),
        earlyLeaveTime: _nullableString(json, 'earlyLeaveTime'),
        returnTime: _nullableString(json, 'returnTime'),
      );
    } catch (_) {
      await preferences.remove(storageKey);
      return DailyAttendanceStatus.unqueried(koreaDate);
    }
  }

  Future<void> save(DailyAttendanceStatus status) async {
    assert(status.queried);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      storageKey,
      jsonEncode({
        'date': _formatDate(status.koreaDate),
        'fetchedAt': status.fetchedAt!.toIso8601String(),
        if (status.checkInTime != null) 'checkInTime': status.checkInTime,
        if (status.checkOutTime != null) 'checkOutTime': status.checkOutTime,
        if (status.earlyLeaveTime != null)
          'earlyLeaveTime': status.earlyLeaveTime,
        if (status.returnTime != null) 'returnTime': status.returnTime,
      }),
    );
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }

  String? _nullableString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value != null && value is! String) throw const FormatException();
    return value as String?;
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

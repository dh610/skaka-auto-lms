import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/daily_attendance_status.dart';

class AttendanceStatusStore {
  static const storageKey = 'attendance.todayStatus';
  static final _timestampPattern = RegExp(
    r'^([+-]?\d{4,6})-(\d{2})-(\d{2})T'
    r'(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?'
    r'(?:Z|([+-])(\d{2}):?(\d{2}))?$',
  );
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
        fetchedAt: _parseTimestamp(fetchedAt),
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

  DateTime _parseTimestamp(String value) {
    final match = _timestampPattern.firstMatch(value);
    if (match == null) throw const FormatException();

    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final hour = int.parse(match[4]!);
    final minute = int.parse(match[5]!);
    final second = int.parse(match[6]!);
    final fraction = (match[7] ?? '').padRight(6, '0');
    final microseconds = int.tryParse(fraction) ?? 0;
    final parsedComponents = DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      microseconds ~/ 1000,
      microseconds % 1000,
    );
    if (parsedComponents.year != year ||
        parsedComponents.month != month ||
        parsedComponents.day != day ||
        parsedComponents.hour != hour ||
        parsedComponents.minute != minute ||
        parsedComponents.second != second ||
        parsedComponents.millisecond != microseconds ~/ 1000 ||
        parsedComponents.microsecond != microseconds % 1000 ||
        (match[9] != null && int.parse(match[9]!) > 23) ||
        (match[10] != null && int.parse(match[10]!) > 59)) {
      throw const FormatException();
    }
    return DateTime.parse(value);
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

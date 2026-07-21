import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AttendanceCompletionStore {
  static const _completionKey = 'attendance.completedAt';
  static const _skippedKey = 'attendance.skippedAt';
  static const _separator = '::';

  static String occurrenceKey(String scheduleId, DateTime scheduledAt) {
    final normalized = DateTime(
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
      scheduledAt.hour,
      scheduledAt.minute,
    );
    return '$scheduleId$_separator${normalized.millisecondsSinceEpoch}';
  }

  Future<Map<String, DateTime>> loadFor(DateTime date) async {
    return _loadFor(_completionKey, date);
  }

  Future<Map<String, DateTime>> loadSkippedFor(DateTime date) async {
    return _loadFor(_skippedKey, date);
  }

  Future<Map<String, DateTime>> _loadFor(
    String storageKey,
    DateTime date,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(storageKey);
    if (encoded == null) return {};
    try {
      final values = jsonDecode(encoded) as Map<String, dynamic>;
      final completedAt = <String, DateTime>{};
      for (final entry in values.entries) {
        final scheduledAt = _scheduledAtFromKey(entry.key);
        final timestamp = DateTime.parse(entry.value as String);
        if (scheduledAt != null && _isSameDate(scheduledAt, date)) {
          completedAt[entry.key] = timestamp;
        }
      }
      if (completedAt.length != values.length) {
        await _save(storageKey, completedAt);
      }
      return completedAt;
    } catch (_) {
      await preferences.remove(storageKey);
      return {};
    }
  }

  Future<void> save(Map<String, DateTime> completedAt) async {
    await _save(_completionKey, completedAt);
  }

  Future<void> saveSkipped(Map<String, DateTime> skippedAt) async {
    await _save(_skippedKey, skippedAt);
  }

  Future<void> _save(String storageKey, Map<String, DateTime> values) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      storageKey,
      jsonEncode({
        for (final entry in values.entries)
          entry.key: entry.value.toIso8601String(),
      }),
    );
  }

  DateTime? _scheduledAtFromKey(String key) {
    final separatorIndex = key.lastIndexOf(_separator);
    if (separatorIndex == -1) return null;
    final milliseconds = int.tryParse(
      key.substring(separatorIndex + _separator.length),
    );
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  bool _isSameDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_completionKey);
    await preferences.remove(_skippedKey);
  }
}

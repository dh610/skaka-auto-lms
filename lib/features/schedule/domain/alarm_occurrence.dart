import 'dart:convert';

import 'attendance_schedule.dart';

class AlarmOccurrence {
  const AlarmOccurrence({
    required this.schedule,
    required this.scheduledAt,
    this.snoozeCount = 0,
  });

  final AttendanceSchedule schedule;
  final DateTime scheduledAt;
  final int snoozeCount;

  String get occurrenceKey => '${schedule.id}@${scheduledAt.toIso8601String()}';

  String get attendancePayload => jsonEncode({
    'scheduleId': schedule.id,
    'action': schedule.action.name,
    'scheduledAt': scheduledAt.toIso8601String(),
  });

  Map<String, dynamic> toPlatformMap() => {
    'occurrenceKey': occurrenceKey,
    'scheduleId': schedule.id,
    'action': schedule.action.name,
    'actionLabel': schedule.action.label,
    'scheduledAtMillis': scheduledAt.millisecondsSinceEpoch,
    'scheduledAtIso': scheduledAt.toIso8601String(),
    'soundUri': schedule.alarmSettings.sound.uri,
    'soundLabel': schedule.alarmSettings.sound.label,
    'volumePercent': schedule.alarmSettings.volumePercent,
    'vibrationEnabled': schedule.alarmSettings.vibrationEnabled,
    'gradualVolumeEnabled': schedule.alarmSettings.gradualVolumeEnabled,
    'snoozeMinutes': schedule.alarmSettings.snoozeMinutes,
    'maximumSnoozeCount': schedule.alarmSettings.maximumSnoozeCount,
    'snoozeCount': snoozeCount,
    'attendancePayload': attendancePayload,
  };
}

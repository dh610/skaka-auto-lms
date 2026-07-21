import '../../schedule/domain/attendance_schedule.dart';

enum TodayScheduleStatus { upcoming, completed, skipped, overdue }

TodayScheduleStatus statusForTodaySchedule(
  AttendanceSchedule schedule, {
  required DateTime now,
  bool persistedCompleted = false,
  bool persistedSkipped = false,
}) {
  if (persistedCompleted) {
    return TodayScheduleStatus.completed;
  }
  if (persistedSkipped) {
    return TodayScheduleStatus.skipped;
  }
  final scheduledAt = DateTime(
    now.year,
    now.month,
    now.day,
    schedule.hour,
    schedule.minute,
  );
  return scheduledAt.isBefore(now)
      ? TodayScheduleStatus.overdue
      : TodayScheduleStatus.upcoming;
}

import '../../schedule/domain/attendance_schedule.dart';

enum TodayScheduleStatus { upcoming, completed, overdue }

TodayScheduleStatus statusForTodaySchedule(
  AttendanceSchedule schedule, {
  required DateTime now,
  bool persistedCompleted = false,
}) {
  if (persistedCompleted) {
    return TodayScheduleStatus.completed;
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

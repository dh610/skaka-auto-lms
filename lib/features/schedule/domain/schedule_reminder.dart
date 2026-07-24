import 'attendance_schedule.dart';
import 'training_calendar.dart';

class ScheduleReminder {
  const ScheduleReminder({required this.schedule, required this.dateTime});

  final AttendanceSchedule schedule;
  final DateTime dateTime;
}

class ScheduleReminderPlanner {
  const ScheduleReminderPlanner._();

  static const maximumPendingReminders = 60;

  static List<ScheduleReminder> plan(
    List<AttendanceSchedule> schedules, {
    required DateTime now,
  }) {
    final startDate = _laterDate(
      DateTime(now.year, now.month, now.day),
      TrainingCalendar.courseStart,
    );
    final reminders = <ScheduleReminder>[];
    for (
      var date = startDate;
      !date.isAfter(TrainingCalendar.courseEnd);
      date = date.add(const Duration(days: 1))
    ) {
      for (final schedule in schedules) {
        if (!_occursOn(schedule, date)) continue;
        final dateTime = _dateTimeFor(schedule, date);
        if (dateTime == schedule.skippedOccurrenceAt) continue;
        if (dateTime.isAfter(now)) {
          reminders.add(
            ScheduleReminder(schedule: schedule, dateTime: dateTime),
          );
        }
      }
    }
    reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return reminders.take(maximumPendingReminders).toList();
  }

  static List<DateTime> nextOccurrenceTimes(
    AttendanceSchedule schedule, {
    required DateTime now,
    int limit = 2,
  }) {
    if (limit <= 0) return const [];
    final startDate = _laterDate(
      DateTime(now.year, now.month, now.day),
      TrainingCalendar.courseStart,
    );
    final occurrences = <DateTime>[];
    for (
      var date = startDate;
      !date.isAfter(TrainingCalendar.courseEnd) && occurrences.length < limit;
      date = date.add(const Duration(days: 1))
    ) {
      if (!_occursOnIgnoringEnabled(schedule, date)) continue;
      final dateTime = _dateTimeFor(schedule, date);
      if (dateTime.isAfter(now)) occurrences.add(dateTime);
    }
    return occurrences;
  }

  static bool _occursOn(AttendanceSchedule schedule, DateTime date) {
    if (!schedule.enabled) return false;
    return _occursOnIgnoringEnabled(schedule, date);
  }

  static bool _occursOnIgnoringEnabled(
    AttendanceSchedule schedule,
    DateTime date,
  ) {
    final matchesRecurrence = schedule.recurrence == ScheduleRecurrence.weekly
        ? schedule.weekdays.contains(date.weekday)
        : isSameDate(schedule.date!, date);
    if (!matchesRecurrence) return false;
    return schedule.recurrence == ScheduleRecurrence.once ||
        !schedule.excludePublicHolidays ||
        !TrainingCalendar.isPublicHoliday(date);
  }

  static DateTime _dateTimeFor(AttendanceSchedule schedule, DateTime date) =>
      DateTime(date.year, date.month, date.day, schedule.hour, schedule.minute);

  static DateTime _laterDate(DateTime first, DateTime second) {
    return first.isAfter(second) ? first : second;
  }
}

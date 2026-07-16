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
        final dateTime = DateTime(
          date.year,
          date.month,
          date.day,
          schedule.hour,
          schedule.minute,
        );
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

  static bool _occursOn(AttendanceSchedule schedule, DateTime date) {
    if (!schedule.matches(date)) return false;
    return schedule.recurrence == ScheduleRecurrence.once ||
        !schedule.excludePublicHolidays ||
        !TrainingCalendar.isPublicHoliday(date);
  }

  static DateTime _laterDate(DateTime first, DateTime second) {
    return first.isAfter(second) ? first : second;
  }
}

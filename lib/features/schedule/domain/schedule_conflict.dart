import 'attendance_schedule.dart';
import 'training_calendar.dart';

class ScheduleConflict {
  const ScheduleConflict({
    required this.existingSchedule,
    required this.occurrenceDate,
  });

  final AttendanceSchedule existingSchedule;
  final DateTime occurrenceDate;

  String get message =>
      '${occurrenceDate.year}년 ${occurrenceDate.month}월 ${occurrenceDate.day}일 '
      '${existingSchedule.displayTime}에 이미 '
      '${existingSchedule.action.label} 일정이 있습니다.\n'
      '기존 일정을 수정하거나 다른 시각을 선택해주세요.';
}

ScheduleConflict? findScheduleConflict(
  AttendanceSchedule candidate,
  Iterable<AttendanceSchedule> existingSchedules,
) {
  for (final existing in existingSchedules) {
    if (existing.id == candidate.id ||
        existing.hour != candidate.hour ||
        existing.minute != candidate.minute) {
      continue;
    }
    for (
      var date = TrainingCalendar.courseStart;
      !date.isAfter(TrainingCalendar.courseEnd);
      date = date.add(const Duration(days: 1))
    ) {
      if (_occursOn(candidate, date) && _occursOn(existing, date)) {
        return ScheduleConflict(
          existingSchedule: existing,
          occurrenceDate: date,
        );
      }
    }
  }
  return null;
}

bool _occursOn(AttendanceSchedule schedule, DateTime date) {
  if (schedule.recurrence == ScheduleRecurrence.once) {
    return isSameDate(schedule.date!, date);
  }
  if (!schedule.weekdays.contains(date.weekday)) return false;
  return !schedule.excludePublicHolidays ||
      !TrainingCalendar.isPublicHoliday(date);
}

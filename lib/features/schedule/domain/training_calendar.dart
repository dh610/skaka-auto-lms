import 'attendance_schedule.dart';

class TrainingCalendar {
  const TrainingCalendar._();

  static final courseStart = DateTime(2026, 7, 14);
  static final courseEnd = DateTime(2026, 12, 18);

  static const publicHolidays = <String, String>{
    '2026-07-17': '제헌절',
    '2026-08-15': '광복절',
    '2026-08-17': '대체공휴일(광복절)',
    '2026-09-24': '추석',
    '2026-09-25': '추석',
    '2026-09-26': '추석',
    '2026-10-03': '개천절',
    '2026-10-05': '대체공휴일(개천절)',
    '2026-10-09': '한글날',
  };

  static bool isWithinCourse(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    return !target.isBefore(courseStart) && !target.isAfter(courseEnd);
  }

  static bool isPublicHoliday(DateTime date) {
    return publicHolidays.containsKey(formatIsoDate(date));
  }

  static String? holidayName(DateTime date) {
    return publicHolidays[formatIsoDate(date)];
  }

  static List<({DateTime date, String name})> holidaysForWeekdays(
    Set<int> weekdays,
  ) {
    return publicHolidays.entries
        .map((entry) => (date: DateTime.parse(entry.key), name: entry.value))
        .where((holiday) => weekdays.contains(holiday.date.weekday))
        .toList();
  }
}

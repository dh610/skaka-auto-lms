enum AttendanceAction {
  checkIn('입실', 'CHECK_IN'),
  checkOut('퇴실', 'CHECK_OUT'),
  leave('외출', 'EARLY_LEAVE'),
  returnFromLeave('복귀', 'RETURN_AFTER_EARLY');

  const AttendanceAction(this.label, this.eventType);

  final String label;
  final String eventType;
}

enum ScheduleRecurrence {
  weekly('요일 반복'),
  once('날짜 지정');

  const ScheduleRecurrence(this.label);

  final String label;
}

class AttendanceSchedule {
  const AttendanceSchedule({
    required this.id,
    required this.action,
    required this.hour,
    required this.minute,
    required this.weekdays,
    required this.enabled,
    this.recurrence = ScheduleRecurrence.weekly,
    this.date,
    this.excludePublicHolidays = true,
  }) : assert(recurrence == ScheduleRecurrence.weekly || date != null);

  factory AttendanceSchedule.fromJson(Map<String, dynamic> json) {
    final recurrenceName = json['recurrence'] as String?;
    final dateValue = json['date'] as String?;
    return AttendanceSchedule(
      id: json['id'] as String,
      action: AttendanceAction.values.byName(json['action'] as String),
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      weekdays: (json['weekdays'] as List<dynamic>? ?? const [])
          .cast<int>()
          .toSet(),
      enabled: json['enabled'] as bool? ?? true,
      recurrence: recurrenceName == null
          ? ScheduleRecurrence.weekly
          : ScheduleRecurrence.values.byName(recurrenceName),
      date: dateValue == null ? null : DateTime.parse(dateValue),
      excludePublicHolidays: json['excludePublicHolidays'] as bool? ?? true,
    );
  }

  final String id;
  final AttendanceAction action;
  final int hour;
  final int minute;
  final Set<int> weekdays;
  final bool enabled;
  final ScheduleRecurrence recurrence;
  final DateTime? date;
  final bool excludePublicHolidays;

  int get minutesSinceMidnight => hour * 60 + minute;

  String get formattedTime =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get displayTime => formatDisplayTime(hour, minute);

  String get recurrenceLabel {
    if (recurrence == ScheduleRecurrence.weekly) {
      final days = formatWeekdays(weekdays);
      return excludePublicHolidays ? '$days · 공휴일 제외' : days;
    }
    return formatDate(date!);
  }

  bool matches(DateTime target) {
    if (!enabled) return false;
    if (recurrence == ScheduleRecurrence.weekly) {
      return weekdays.contains(target.weekday);
    }
    return isSameDate(date!, target);
  }

  AttendanceSchedule copyWith({
    AttendanceAction? action,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    bool? enabled,
    ScheduleRecurrence? recurrence,
    DateTime? date,
    bool? excludePublicHolidays,
  }) {
    return AttendanceSchedule(
      id: id,
      action: action ?? this.action,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weekdays: weekdays ?? this.weekdays,
      enabled: enabled ?? this.enabled,
      recurrence: recurrence ?? this.recurrence,
      date: date ?? this.date,
      excludePublicHolidays:
          excludePublicHolidays ?? this.excludePublicHolidays,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action.name,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays.toList()..sort(),
    'enabled': enabled,
    'recurrence': recurrence.name,
    'date': date == null ? null : formatIsoDate(date!),
    'excludePublicHolidays': excludePublicHolidays,
  };
}

const weekdayLabels = <int, String>{
  DateTime.monday: '월',
  DateTime.tuesday: '화',
  DateTime.wednesday: '수',
  DateTime.thursday: '목',
  DateTime.friday: '금',
  DateTime.saturday: '토',
  DateTime.sunday: '일',
};

String formatWeekdays(Set<int> weekdays) {
  const weekdaysOnly = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };
  if (weekdays.length == 7) return '매일';
  if (weekdays.length == 5 && weekdays.containsAll(weekdaysOnly)) return '평일';
  return weekdayLabels.entries
      .where((entry) => weekdays.contains(entry.key))
      .map((entry) => entry.value)
      .join('·');
}

String formatIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String formatDate(DateTime date) => '${date.year}. ${date.month}. ${date.day}.';

String formatDisplayTime(int hour, int minute) {
  final period = hour < 12 ? '오전' : '오후';
  final displayHour = switch (hour % 12) {
    0 => 12,
    final value => value,
  };
  return '$period $displayHour:${minute.toString().padLeft(2, '0')}';
}

bool isSameDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

enum AttendanceAction {
  checkIn('입실', 'CHECK_IN'),
  checkOut('퇴실', 'CHECK_OUT'),
  leave('외출', 'EARLY_LEAVE'),
  returnFromLeave('복귀', 'RETURN_AFTER_EARLY');

  const AttendanceAction(this.label, this.eventType);

  final String label;
  final String eventType;
}

class AttendanceSchedule {
  const AttendanceSchedule({
    required this.id,
    required this.action,
    required this.hour,
    required this.minute,
    required this.weekdays,
    required this.enabled,
  });

  factory AttendanceSchedule.fromJson(Map<String, dynamic> json) {
    return AttendanceSchedule(
      id: json['id'] as String,
      action: AttendanceAction.values.byName(json['action'] as String),
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      weekdays: (json['weekdays'] as List<dynamic>).cast<int>().toSet(),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  final String id;
  final AttendanceAction action;
  final int hour;
  final int minute;
  final Set<int> weekdays;
  final bool enabled;

  int get minutesSinceMidnight => hour * 60 + minute;

  String get formattedTime =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  bool occursOn(DateTime date) => enabled && weekdays.contains(date.weekday);

  AttendanceSchedule copyWith({
    AttendanceAction? action,
    int? hour,
    int? minute,
    Set<int>? weekdays,
    bool? enabled,
  }) {
    return AttendanceSchedule(
      id: id,
      action: action ?? this.action,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      weekdays: weekdays ?? this.weekdays,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action.name,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays.toList()..sort(),
    'enabled': enabled,
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

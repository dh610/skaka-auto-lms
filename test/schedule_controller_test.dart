import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/features/schedule/application/schedule_controller.dart';
import 'package:skala_attendance/features/schedule/data/schedule_store.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';
import 'package:skala_attendance/features/schedule/domain/training_calendar.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('schedule JSON round trip preserves all fields', () {
    const schedule = AttendanceSchedule(
      id: 'check-in',
      action: AttendanceAction.checkIn,
      hour: 9,
      minute: 5,
      weekdays: {1, 2, 3, 4, 5},
      enabled: true,
    );

    final restored = AttendanceSchedule.fromJson(schedule.toJson());

    expect(restored.id, schedule.id);
    expect(restored.action, schedule.action);
    expect(restored.formattedTime, '09:05');
    expect(restored.displayTime, '오전 9:05');
    expect(restored.weekdays, schedule.weekdays);
    expect(restored.enabled, isTrue);
  });

  test('controller persists, sorts, toggles and deletes schedules', () async {
    final controller = ScheduleController(ScheduleStore());
    await controller.load();
    const checkOut = AttendanceSchedule(
      id: 'check-out',
      action: AttendanceAction.checkOut,
      hour: 17,
      minute: 55,
      weekdays: {1, 2, 3, 4, 5},
      enabled: true,
    );
    const checkIn = AttendanceSchedule(
      id: 'check-in',
      action: AttendanceAction.checkIn,
      hour: 9,
      minute: 5,
      weekdays: {1, 2, 3, 4, 5},
      enabled: true,
    );

    await controller.saveSchedule(checkOut);
    await controller.saveSchedule(checkIn);
    expect(controller.schedules.map((item) => item.id), [
      'check-in',
      'check-out',
    ]);

    await controller.setEnabled(checkIn, false);
    expect(controller.schedulesFor(DateTime(2026, 7, 20)), [checkOut]);

    await controller.delete(checkOut);
    final restored = ScheduleController(ScheduleStore());
    await restored.load();
    expect(restored.schedules.single.id, 'check-in');
    expect(restored.schedules.single.enabled, isFalse);

    controller.dispose();
    restored.dispose();
  });

  test('weekday formatter handles common selections', () {
    expect(formatWeekdays({1, 2, 3, 4, 5}), '평일');
    expect(formatWeekdays({1, 2, 3, 4, 5, 6, 7}), '매일');
    expect(formatWeekdays({1, 3, 5}), '월·수·금');
  });

  test('legacy schedule JSON migrates to holiday-excluding weekly rule', () {
    final schedule = AttendanceSchedule.fromJson({
      'id': 'legacy',
      'action': 'checkIn',
      'hour': 9,
      'minute': 5,
      'weekdays': [1, 2, 3, 4, 5],
      'enabled': true,
    });

    expect(schedule.recurrence, ScheduleRecurrence.weekly);
    expect(schedule.excludePublicHolidays, isTrue);
    expect(schedule.date, isNull);
  });

  test('weekly schedules skip holidays but date schedules remain', () async {
    final controller = ScheduleController(ScheduleStore());
    await controller.load();
    const weekly = AttendanceSchedule(
      id: 'weekly',
      action: AttendanceAction.checkIn,
      hour: 9,
      minute: 5,
      weekdays: {DateTime.friday},
      enabled: true,
    );
    final once = AttendanceSchedule(
      id: 'once',
      action: AttendanceAction.checkIn,
      hour: 10,
      minute: 0,
      weekdays: const {},
      enabled: true,
      recurrence: ScheduleRecurrence.once,
      date: DateTime(2026, 7, 17),
    );
    await controller.saveSchedule(weekly);
    await controller.saveSchedule(once);

    final schedules = controller.schedulesFor(DateTime(2026, 7, 17));

    expect(TrainingCalendar.holidayName(DateTime(2026, 7, 17)), '제헌절');
    expect(schedules.map((schedule) => schedule.id), ['once']);
    controller.dispose();
  });

  test('course calendar contains official holidays returned by the API', () {
    expect(TrainingCalendar.publicHolidays, hasLength(9));
    expect(TrainingCalendar.holidayName(DateTime(2026, 8, 17)), '대체공휴일(광복절)');
    expect(TrainingCalendar.holidayName(DateTime(2026, 10, 5)), '대체공휴일(개천절)');
    final weekdayHolidays = TrainingCalendar.holidaysForWeekdays({
      1,
      2,
      3,
      4,
      5,
    });
    expect(weekdayHolidays, hasLength(6));
    expect(weekdayHolidays.map((holiday) => holiday.name), contains('제헌절'));
    expect(
      weekdayHolidays.map((holiday) => holiday.name),
      isNot(contains('광복절')),
    );
  });
}

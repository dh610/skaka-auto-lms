import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/features/schedule/application/schedule_controller.dart';
import 'package:skala_attendance/features/schedule/data/schedule_store.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';
import 'package:skala_attendance/features/schedule/domain/schedule_conflict.dart';

void main() {
  const mondayMorning = AttendanceSchedule(
    id: 'monday-check-in',
    action: AttendanceAction.checkIn,
    hour: 7,
    minute: 32,
    weekdays: {DateTime.monday},
    enabled: true,
  );

  test('weekly schedules conflict when a weekday and time overlap', () {
    const candidate = AttendanceSchedule(
      id: 'weekday-leave',
      action: AttendanceAction.leave,
      hour: 7,
      minute: 32,
      weekdays: {DateTime.monday, DateTime.wednesday},
      enabled: true,
    );

    final conflict = findScheduleConflict(candidate, [mondayMorning]);

    expect(conflict, isNotNull);
    expect(conflict!.occurrenceDate, DateTime(2026, 7, 20));
    expect(conflict.message, contains('오전 7:32에 이미 입실 일정'));
  });

  test('same time on non-overlapping weekdays is allowed', () {
    const candidate = AttendanceSchedule(
      id: 'tuesday-check-out',
      action: AttendanceAction.checkOut,
      hour: 7,
      minute: 32,
      weekdays: {DateTime.tuesday},
      enabled: true,
    );

    expect(findScheduleConflict(candidate, [mondayMorning]), isNull);
  });

  test('one-time schedule conflicts with a weekly occurrence', () {
    final candidate = AttendanceSchedule(
      id: 'once-return',
      action: AttendanceAction.returnFromLeave,
      hour: 7,
      minute: 32,
      weekdays: const {},
      enabled: true,
      recurrence: ScheduleRecurrence.once,
      date: DateTime(2026, 7, 20),
    );

    expect(findScheduleConflict(candidate, [mondayMorning]), isNotNull);
  });

  test('holiday exclusion prevents a conflict that cannot occur', () {
    const holidayWeekly = AttendanceSchedule(
      id: 'friday-check-in',
      action: AttendanceAction.checkIn,
      hour: 9,
      minute: 0,
      weekdays: {DateTime.friday},
      enabled: false,
      excludePublicHolidays: true,
    );
    final holidayOnce = AttendanceSchedule(
      id: 'holiday-once',
      action: AttendanceAction.leave,
      hour: 9,
      minute: 0,
      weekdays: const {},
      enabled: true,
      recurrence: ScheduleRecurrence.once,
      date: DateTime(2026, 7, 17),
    );

    expect(findScheduleConflict(holidayOnce, [holidayWeekly]), isNull);
    expect(
      findScheduleConflict(holidayOnce, [
        holidayWeekly.copyWith(excludePublicHolidays: false),
      ]),
      isNotNull,
    );
  });

  test('editing a schedule excludes itself from conflict checks', () {
    expect(findScheduleConflict(mondayMorning, [mondayMorning]), isNull);
  });

  test(
    'controller rejects a conflicting schedule without persisting it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final controller = ScheduleController(ScheduleStore());
      await controller.load();
      await controller.saveSchedule(mondayMorning);
      const duplicate = AttendanceSchedule(
        id: 'duplicate',
        action: AttendanceAction.checkOut,
        hour: 7,
        minute: 32,
        weekdays: {DateTime.monday},
        enabled: false,
      );

      final conflict = await controller.saveSchedule(duplicate);

      expect(conflict, isNotNull);
      expect(controller.schedules, [mondayMorning]);
      final restored = ScheduleController(ScheduleStore());
      await restored.load();
      expect(restored.schedules.map((schedule) => schedule.id), [
        mondayMorning.id,
      ]);
      controller.dispose();
      restored.dispose();
    },
  );
}

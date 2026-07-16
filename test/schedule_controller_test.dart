import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/features/schedule/application/schedule_controller.dart';
import 'package:skala_attendance/features/schedule/data/schedule_store.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';

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
    expect(controller.schedulesFor(DateTime(2026, 7, 13)), [checkOut]);

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
}

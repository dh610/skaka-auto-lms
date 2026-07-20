import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/features/schedule/application/notification_scheduler.dart';
import 'package:skala_attendance/features/schedule/application/schedule_controller.dart';
import 'package:skala_attendance/features/schedule/data/schedule_store.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';
import 'package:skala_attendance/features/schedule/domain/schedule_reminder.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('planner skips holidays and past occurrences', () {
    const schedule = AttendanceSchedule(
      id: 'weekday-check-in',
      action: AttendanceAction.checkIn,
      hour: 9,
      minute: 5,
      weekdays: {1, 2, 3, 4, 5},
      enabled: true,
    );

    final reminders = ScheduleReminderPlanner.plan([
      schedule,
    ], now: DateTime(2026, 7, 16, 10));

    expect(reminders.first.dateTime, DateTime(2026, 7, 20, 9, 5));
    expect(
      reminders.any((item) => item.dateTime == DateTime(2026, 7, 17, 9, 5)),
      isFalse,
    );
  });

  test('one-time holiday reminder remains scheduled', () {
    final schedule = AttendanceSchedule(
      id: 'holiday-once',
      action: AttendanceAction.checkIn,
      hour: 10,
      minute: 0,
      weekdays: const {},
      enabled: true,
      recurrence: ScheduleRecurrence.once,
      date: DateTime(2026, 7, 17),
    );

    final reminders = ScheduleReminderPlanner.plan([
      schedule,
    ], now: DateTime(2026, 7, 16));

    expect(reminders.single.dateTime, DateTime(2026, 7, 17, 10));
  });

  test('controller requests permission and resyncs after save', () async {
    final notifications = _FakeNotificationScheduler();
    final controller = ScheduleController(ScheduleStore(), notifications);
    await controller.load();
    const schedule = AttendanceSchedule(
      id: 'check-in',
      action: AttendanceAction.checkIn,
      hour: 9,
      minute: 5,
      weekdays: {1, 2, 3, 4, 5},
      enabled: true,
    );

    await controller.saveSchedule(schedule);

    expect(notifications.permissionRequests, 1);
    expect(notifications.lastSchedules, [schedule]);
    expect(controller.pendingNotificationCount, 1);
    expect(controller.notificationsConfigured, isTrue);
    controller.dispose();
  });
}

class _FakeNotificationScheduler implements NotificationScheduler {
  final _tapPayload = ValueNotifier<String?>(null);
  int permissionRequests = 0;
  List<AttendanceSchedule> lastSchedules = [];

  @override
  Future<bool> arePermissionsGranted() async => false;

  @override
  ValueListenable<String?> get tapPayload => _tapPayload;

  @override
  void consumeTap() => _tapPayload.value = null;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now}) async {
    lastSchedules = schedules.toList();
    return schedules.length;
  }
}

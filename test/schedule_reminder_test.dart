import 'dart:async';

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

  test(
    'stored schedules are visible before notification sync finishes',
    () async {
      final syncGate = Completer<void>();
      final notifications = _FakeNotificationScheduler(syncGate: syncGate);
      final controller = ScheduleController(ScheduleStore(), notifications);
      final schedulesLoaded = Completer<void>();
      controller.addListener(() {
        if (!controller.loading && !schedulesLoaded.isCompleted) {
          schedulesLoaded.complete();
        }
      });

      final loadFuture = controller.load();
      await schedulesLoaded.future;

      expect(controller.loading, isFalse);
      expect(syncGate.isCompleted, isFalse);

      syncGate.complete();
      await loadFuture;
      controller.dispose();
    },
  );

  test(
    'overlapping resync requests run serially and finish with latest schedules',
    () async {
      final notifications = _GatedNotificationScheduler();
      final controller = ScheduleController(ScheduleStore(), notifications);

      final loadFuture = controller.load();
      await notifications.firstSyncStarted.future;

      const latest = AttendanceSchedule(
        id: 'weekday-check-out',
        action: AttendanceAction.checkOut,
        hour: 18,
        minute: 30,
        weekdays: {1, 2, 3, 4, 5},
        enabled: true,
      );
      final saveFuture = controller.saveSchedule(latest);
      await notifications.permissionRequested.future;
      await Future<void>.delayed(Duration.zero);

      expect(notifications.maximumActiveSyncs, 1);
      expect(notifications.snapshots, hasLength(1));

      notifications.releaseFirstSync.complete();
      await Future.wait([loadFuture, saveFuture]);

      expect(notifications.maximumActiveSyncs, 1);
      expect(notifications.snapshots, hasLength(2));
      expect(notifications.snapshots.first, isEmpty);
      expect(notifications.snapshots.last, [latest]);
      controller.dispose();
    },
  );

  test('startup resync uses the latest persisted schedules', () async {
    const latest = AttendanceSchedule(
      id: 'persisted-check-out',
      action: AttendanceAction.checkOut,
      hour: 18,
      minute: 30,
      weekdays: {1, 2, 3, 4, 5},
      enabled: true,
    );
    await ScheduleStore().save([latest]);
    final notifications = _FakeNotificationScheduler();
    final restored = ScheduleController(ScheduleStore(), notifications);

    await restored.load();

    expect(notifications.lastSchedules.single.toJson(), latest.toJson());
    restored.dispose();
  });
}

class _FakeNotificationScheduler implements NotificationScheduler {
  _FakeNotificationScheduler({this.syncGate});

  final _tapPayload = ValueNotifier<String?>(null);
  final Completer<void>? syncGate;
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
  Future<void> openPermissionSettings() async {}

  @override
  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now}) async {
    lastSchedules = schedules.toList();
    await syncGate?.future;
    return schedules.length;
  }
}

class _GatedNotificationScheduler extends _FakeNotificationScheduler {
  final firstSyncStarted = Completer<void>();
  final releaseFirstSync = Completer<void>();
  final permissionRequested = Completer<void>();
  final List<List<AttendanceSchedule>> snapshots = [];
  int activeSyncs = 0;
  int maximumActiveSyncs = 0;

  @override
  Future<bool> requestPermissions() async {
    if (!permissionRequested.isCompleted) permissionRequested.complete();
    return true;
  }

  @override
  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now}) async {
    final snapshot = List<AttendanceSchedule>.of(schedules);
    snapshots.add(snapshot);
    activeSyncs++;
    if (activeSyncs > maximumActiveSyncs) maximumActiveSyncs = activeSyncs;
    try {
      if (snapshots.length == 1) {
        firstSyncStarted.complete();
        await releaseFirstSync.future;
      }
      return snapshot.length;
    } finally {
      activeSyncs--;
    }
  }
}

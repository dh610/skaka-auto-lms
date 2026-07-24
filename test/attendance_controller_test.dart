import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/features/attendance/application/attendance_controller.dart';
import 'package:skala_attendance/features/attendance/data/attendance_completion_store.dart';
import 'package:skala_attendance/features/attendance/data/attendance_gateway.dart';
import 'package:skala_attendance/features/attendance/domain/attendance_snapshot.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';

void main() {
  const profile = UserProfile(
    name: '윤동현',
    region: CampusRegion.pangyo5f,
    classNumber: 8,
  );

  test('starts browser authentication with the current profile', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);

    await controller.startAuthentication();

    expect(gateway.authenticationProfile, same(profile));
    expect(controller.busy, isFalse);
    expect(controller.message, contains('Chrome'));
    controller.dispose();
  });

  test('valid callback fetches and exposes today attendance', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);

    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    expect(gateway.validatedToken, 'test-token');
    expect(gateway.fetchedToken, 'test-token');
    expect(controller.snapshot, same(gateway.snapshot));
    expect(controller.message, '인증 및 상태 조회에 성공했습니다.');
    expect(controller.statusRevision, 1);
    expect(controller.completionRevision, 0);
    expect(controller.lastCompletedAction, isNull);
    controller.dispose();
  });

  test('scheduled authentication survives controller recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final scheduledAt = now.subtract(const Duration(minutes: 1));
    final schedule = AttendanceSchedule(
      id: 'today-check-in',
      action: AttendanceAction.checkIn,
      hour: scheduledAt.hour,
      minute: scheduledAt.minute,
      weekdays: {scheduledAt.weekday},
      enabled: true,
    );
    final store = AttendanceCompletionStore();
    final first = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      isAndroid: true,
      completionStore: store,
    );
    await first.startAuthentication(
      scheduleId: schedule.id,
      scheduledAt: scheduledAt,
    );
    first.dispose();

    final restored = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      isAndroid: true,
      completionStore: store,
    );
    await restored.loadCompletionHistory();

    expect(restored.wasScheduleCompleted(schedule, now), isTrue);
    restored.dispose();
  });

  test('manual skip can be persisted and reverted', () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 7, 21, 10);
    const schedule = AttendanceSchedule(
      id: 'optional-leave',
      action: AttendanceAction.leave,
      hour: 9,
      minute: 30,
      weekdays: {DateTime.tuesday},
      enabled: true,
    );
    final store = AttendanceCompletionStore();
    final controller = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      completionStore: store,
    );

    await controller.setScheduleSkipped(schedule, now, skipped: true);
    expect(controller.wasScheduleSkipped(schedule, now), isTrue);

    final restored = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      completionStore: store,
    );
    await restored.loadCompletionHistory(now: now);
    expect(restored.wasScheduleSkipped(schedule, now), isTrue);

    await restored.setScheduleSkipped(schedule, now, skipped: false);
    expect(restored.wasScheduleSkipped(schedule, now), isFalse);
    controller.dispose();
    restored.dispose();
  });

  test('ignores callbacks from unrelated hosts', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);

    await controller.handleCallback(
      Uri.parse('https://example.com/?token=test-token'),
    );

    expect(gateway.validatedToken, isNull);
    expect(controller.message, 'Google 인증 후 출결 정보를 확인하세요.');
    controller.dispose();
  });

  test('records an allowed action and refreshes server state', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    await controller.performAction(AttendanceAction.leave);

    expect(gateway.recordedAction, AttendanceAction.leave);
    expect(gateway.recordedToken, 'test-token');
    expect(controller.snapshot?.earlyLeaveTime, '12:00');
    expect(controller.message, '외출 처리가 완료되었습니다.');
    expect(controller.statusRevision, 2);
    expect(controller.completionRevision, 1);
    expect(controller.lastCompletedAction, AttendanceAction.leave);
    controller.dispose();
  });

  test('does not send an action that current state disallows', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    await controller.performAction(AttendanceAction.checkIn);

    expect(gateway.recordedAction, isNull);
    expect(controller.message, contains('현재 출결 상태에서는'));
    controller.dispose();
  });

  test('authentication timeout exposes a friendly retry action', () async {
    final gateway = _FakeAttendanceGateway()
      ..authenticationError = TimeoutException('timed out');
    final controller = AttendanceController(profile, gateway, isAndroid: true);

    await controller.startAuthentication();

    expect(controller.hasError, isTrue);
    expect(controller.canRetry, isTrue);
    expect(controller.retryLabel, 'Google 인증 다시 시도');
    expect(controller.message, contains('응답 시간이 초과되었습니다'));
    expect(controller.message, isNot(contains('TimeoutException')));

    gateway.authenticationError = null;
    await controller.retry();
    expect(gateway.authenticationCallCount, 2);
    expect(controller.hasError, isFalse);
    expect(controller.message, contains('Chrome'));
    controller.dispose();
  });

  test(
    'action failure retries status lookup without resending action',
    () async {
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      gateway.fetchError = TimeoutException('timed out');

      await controller.performAction(AttendanceAction.leave);

      expect(controller.retryLabel, '출결 상태 다시 조회');
      expect(gateway.recordCallCount, 1);
      expect(controller.completionRevision, 0);
      expect(controller.lastCompletedAction, isNull);
      gateway.fetchError = null;
      await controller.retry();
      expect(gateway.recordCallCount, 1);
      expect(controller.snapshot?.earlyLeaveTime, '12:00');
      expect(controller.hasError, isFalse);
      expect(controller.completionRevision, 1);
      expect(controller.lastCompletedAction, AttendanceAction.leave);
      controller.dispose();
    },
  );

  test(
    'status retry stays incomplete until the server reflects the action',
    () async {
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      gateway
        ..fetchError = TimeoutException('timed out')
        ..reflectRecordedAction = false;

      await controller.performAction(AttendanceAction.leave);

      gateway.fetchError = null;
      await controller.retry();

      expect(controller.completionRevision, 0);
      expect(controller.lastCompletedAction, isNull);
      expect(controller.canRetry, isTrue);
      expect(controller.retryLabel, '출결 상태 다시 조회');
      controller.dispose();
    },
  );

  test(
    'definitive action rejection refreshes without waiting for reflection',
    () async {
      final gateway = _FakeAttendanceGateway()
        ..reflectRecordedAction = false
        ..recordError = const AttendanceActionRejectedException('rejected');
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      await controller.performAction(AttendanceAction.leave);

      expect(controller.completionRevision, 0);
      expect(controller.canRetry, isTrue);
      await controller.retry();
      expect(gateway.recordCallCount, 1);
      expect(controller.hasError, isFalse);
      expect(controller.completionRevision, 0);
      expect(
        controller.snapshot?.availableActions,
        contains(AttendanceAction.leave),
      );
      controller.dispose();
    },
  );

  test(
    'ambiguous action timeout completes only after status confirms it',
    () async {
      final gateway = _FakeAttendanceGateway()
        ..recordError = TimeoutException('timed out');
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      await controller.performAction(AttendanceAction.leave);

      expect(controller.completionRevision, 0);
      gateway.recordError = null;
      await controller.retry();
      expect(gateway.recordCallCount, 1);
      expect(controller.completionRevision, 1);
      expect(controller.lastCompletedAction, AttendanceAction.leave);
      controller.dispose();
    },
  );

  test(
    'clears an authenticated snapshot when the Korean date changes',
    () async {
      var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
      final controller = AttendanceController(
        profile,
        _FakeAttendanceGateway(),
        isAndroid: true,
        now: () => now,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      now = DateTime.utc(2026, 7, 24, 15);
      expect(controller.invalidateExpiredDailyState(), isTrue);
      expect(controller.snapshot, isNull);
      expect(controller.authenticated, isFalse);
      expect(controller.retryRequiresAuthentication, isTrue);
      controller.dispose();
    },
  );

  test('available actions follow attendance state order', () {
    expect(const AttendanceSnapshot(networkAllowed: true).availableActions, {
      AttendanceAction.checkIn,
    });
    expect(
      const AttendanceSnapshot(
        networkAllowed: true,
        checkInTime: '09:00',
      ).availableActions,
      {AttendanceAction.leave, AttendanceAction.checkOut},
    );
    expect(
      const AttendanceSnapshot(
        networkAllowed: true,
        checkInTime: '09:00',
        earlyLeaveTime: '12:00',
      ).availableActions,
      {AttendanceAction.returnFromLeave},
    );
    expect(
      const AttendanceSnapshot(networkAllowed: false).availableActions,
      isEmpty,
    );
  });
}

class _FakeAttendanceGateway implements AttendanceGateway {
  AttendanceSnapshot snapshot = const AttendanceSnapshot(
    networkAllowed: true,
    checkInTime: '09:00',
  );

  UserProfile? authenticationProfile;
  String? validatedToken;
  String? fetchedToken;
  String? recordedToken;
  AttendanceAction? recordedAction;
  Object? authenticationError;
  Object? fetchError;
  Object? recordError;
  bool reflectRecordedAction = true;
  int recordCallCount = 0;
  int authenticationCallCount = 0;

  @override
  Future<void> startBrowserAuthentication(UserProfile profile) async {
    authenticationCallCount++;
    if (authenticationError case final error?) throw error;
    authenticationProfile = profile;
  }

  @override
  void validateAttendanceToken(String token, UserProfile profile) {
    validatedToken = token;
  }

  @override
  Future<AttendanceSnapshot> fetchToday(String token) async {
    if (fetchError case final error?) throw error;
    fetchedToken = token;
    return snapshot;
  }

  @override
  Future<void> recordAction(String token, AttendanceAction action) async {
    recordCallCount++;
    recordedToken = token;
    recordedAction = action;
    if (action == AttendanceAction.leave && reflectRecordedAction) {
      snapshot = const AttendanceSnapshot(
        networkAllowed: true,
        checkInTime: '09:00',
        earlyLeaveTime: '12:00',
      );
    }
    if (recordError case final error?) throw error;
  }

  @override
  void close() {}
}

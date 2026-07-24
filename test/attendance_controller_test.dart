import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/features/attendance/application/attendance_controller.dart';
import 'package:skala_attendance/features/attendance/data/attendance_completion_store.dart';
import 'package:skala_attendance/features/attendance/data/attendance_gateway.dart';
import 'package:skala_attendance/features/attendance/data/attendance_status_store.dart';
import 'package:skala_attendance/features/attendance/domain/attendance_snapshot.dart';
import 'package:skala_attendance/features/attendance/domain/daily_attendance_status.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';

void main() {
  const profile = UserProfile(
    name: '윤동현',
    region: CampusRegion.pangyo5f,
    classNumber: 8,
  );

  test('starts with an unqueried daily status for the current Korean date', () {
    final now = DateTime.utc(2026, 7, 24, 14, 30);
    final controller = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      now: () => now,
    );

    expect(controller.dailyStatus.koreaDate, DateTime.utc(2026, 7, 24));
    expect(controller.dailyStatus.queried, isFalse);
    controller.dispose();
  });

  test(
    'restores same-day display times without restoring a live session',
    () async {
      final koreaDate = DateTime.utc(2026, 7, 24);
      final fetchedAt = DateTime.utc(2026, 7, 24, 2, 15);
      final store = _FakeAttendanceStatusStore()
        ..savedStatus = DailyAttendanceStatus.queried(
          koreaDate: koreaDate,
          fetchedAt: fetchedAt,
          checkInTime: '09:00',
          checkOutTime: '18:00',
          earlyLeaveTime: '12:00',
          returnTime: '13:00',
        );
      final controller = AttendanceController(
        profile,
        _FakeAttendanceGateway(),
        statusStore: store,
        now: () => DateTime.utc(2026, 7, 24, 3),
      );

      await controller.loadDailyStatus();

      expect(controller.dailyStatus.koreaDate, koreaDate);
      expect(controller.dailyStatus.fetchedAt, fetchedAt);
      expect(controller.dailyStatus.checkInTime, '09:00');
      expect(controller.dailyStatus.checkOutTime, '18:00');
      expect(controller.dailyStatus.earlyLeaveTime, '12:00');
      expect(controller.dailyStatus.returnTime, '13:00');
      expect(controller.snapshot, isNull);
      expect(controller.authenticated, isFalse);
      controller.dispose();
    },
  );

  test('successful callback saves display status for a new controller', () async {
    final now = DateTime.utc(2026, 7, 24, 3);
    final store = _FakeAttendanceStatusStore();
    final first = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      isAndroid: true,
      statusStore: store,
      now: () => now,
    );

    await first.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    expect(first.dailyStatus.queried, isTrue);
    expect(first.dailyStatus.checkInTime, '09:00');
    expect(store.savedStatus?.checkInTime, '09:00');
    first.dispose();

    final restored = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      statusStore: store,
      now: () => now,
    );
    await restored.loadDailyStatus();

    expect(restored.dailyStatus.queried, isTrue);
    expect(restored.snapshot, isNull);
    expect(restored.authenticated, isFalse);
    restored.dispose();
  });

  test('a display-status save failure preserves successful server status', () async {
    final store = _FakeAttendanceStatusStore()..saveError = StateError('full');
    final controller = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      isAndroid: true,
      statusStore: store,
      now: () => DateTime.utc(2026, 7, 24, 3),
    );

    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    expect(controller.dailyStatus.queried, isTrue);
    expect(controller.statusRevision, 1);
    expect(controller.message, '인증 및 상태 조회에 성공했습니다.');
    controller.dispose();
  });

  test('profile changes clear daily display state and persisted status', () async {
    final now = DateTime.utc(2026, 7, 24, 3);
    final store = _FakeAttendanceStatusStore();
    final controller = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      isAndroid: true,
      statusStore: store,
      now: () => now,
    );
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    controller.updateProfile(
      const UserProfile(
        name: '다른 사용자',
        region: CampusRegion.pangyo5f,
        classNumber: 9,
      ),
    );

    expect(controller.dailyStatus.queried, isFalse);
    expect(controller.dailyStatus.koreaDate, DateTime.utc(2026, 7, 24));
    expect(store.savedStatus, isNull);
    expect(store.clearCallCount, 1);
    controller.dispose();
  });

  test('Korean midnight clears daily display state and persisted status', () async {
    var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
    final store = _FakeAttendanceStatusStore();
    final controller = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      isAndroid: true,
      statusStore: store,
      now: () => now,
    );
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    now = DateTime.utc(2026, 7, 24, 15);
    expect(controller.invalidateExpiredDailyState(), isTrue);

    expect(controller.dailyStatus.queried, isFalse);
    expect(controller.dailyStatus.koreaDate, DateTime.utc(2026, 7, 25));
    expect(store.savedStatus, isNull);
    expect(store.clearCallCount, 1);
    controller.dispose();
  });

  test('a stale daily-status load cannot restore state after a profile change', () async {
    final gate = Completer<DailyAttendanceStatus>();
    final store = _FakeAttendanceStatusStore()..loadGate = gate;
    final controller = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      statusStore: store,
      now: () => DateTime.utc(2026, 7, 24, 3),
    );

    final load = controller.loadDailyStatus();
    controller.updateProfile(
      const UserProfile(
        name: '다른 사용자',
        region: CampusRegion.pangyo5f,
        classNumber: 9,
      ),
    );
    gate.complete(
      DailyAttendanceStatus.queried(
        koreaDate: DateTime.utc(2026, 7, 24),
        fetchedAt: DateTime.utc(2026, 7, 24, 3),
        checkInTime: '09:00',
      ),
    );
    await load;

    expect(controller.dailyStatus.queried, isFalse);
    controller.dispose();
  });

  test('a stale daily-status load cannot restore state after Korean midnight', () async {
    var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
    final gate = Completer<DailyAttendanceStatus>();
    final store = _FakeAttendanceStatusStore()..loadGate = gate;
    final controller = AttendanceController(
      profile,
      _FakeAttendanceGateway(),
      statusStore: store,
      now: () => now,
    );

    final load = controller.loadDailyStatus();
    now = DateTime.utc(2026, 7, 24, 15);
    expect(controller.invalidateExpiredDailyState(), isTrue);
    gate.complete(
      DailyAttendanceStatus.queried(
        koreaDate: DateTime.utc(2026, 7, 24),
        fetchedAt: DateTime.utc(2026, 7, 24, 3),
        checkInTime: '09:00',
      ),
    );
    await load;

    expect(controller.dailyStatus.queried, isFalse);
    expect(controller.dailyStatus.koreaDate, DateTime.utc(2026, 7, 25));
    controller.dispose();
  });

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

  test(
    'old action result cannot restore status after Korean midnight',
    () async {
      var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
      final recordGate = Completer<void>();
      final gateway = _FakeAttendanceGateway()..recordGate = recordGate;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        now: () => now,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      final action = controller.performAction(AttendanceAction.leave);
      await Future<void>.delayed(Duration.zero);
      now = DateTime.utc(2026, 7, 24, 15, 0, 1);
      expect(controller.invalidateExpiredDailyState(), isTrue);
      recordGate.complete();
      await action;

      expect(controller.snapshot, isNull);
      expect(controller.authenticated, isFalse);
      expect(controller.completionRevision, 0);
      controller.dispose();
    },
  );

  test(
    'old refresh result cannot restore status after Korean midnight',
    () async {
      var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        now: () => now,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      final fetchGate = Completer<void>();
      gateway.fetchGate = fetchGate;

      final refresh = controller.refreshStatus();
      await Future<void>.delayed(Duration.zero);
      now = DateTime.utc(2026, 7, 24, 15, 0, 1);
      expect(controller.invalidateExpiredDailyState(), isTrue);
      fetchGate.complete();
      await refresh;

      expect(controller.snapshot, isNull);
      expect(controller.authenticated, isFalse);
      controller.dispose();
    },
  );

  test(
    'callback finishing after Korean midnight requires new authentication',
    () async {
      var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
      final fetchGate = Completer<void>();
      final gateway = _FakeAttendanceGateway()..fetchGate = fetchGate;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        now: () => now,
      );

      final callback = controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      await Future<void>.delayed(Duration.zero);
      now = DateTime.utc(2026, 7, 24, 15, 0, 1);
      fetchGate.complete();
      await callback;

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
  Completer<void>? fetchGate;
  Completer<void>? recordGate;
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
    await fetchGate?.future;
    if (fetchError case final error?) throw error;
    fetchedToken = token;
    return snapshot;
  }

  @override
  Future<void> recordAction(String token, AttendanceAction action) async {
    recordCallCount++;
    recordedToken = token;
    recordedAction = action;
    await recordGate?.future;
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

class _FakeAttendanceStatusStore extends AttendanceStatusStore {
  DailyAttendanceStatus? savedStatus;
  Object? saveError;
  Completer<DailyAttendanceStatus>? loadGate;
  int clearCallCount = 0;

  @override
  Future<DailyAttendanceStatus> loadFor(DateTime koreaDate) async {
    if (loadGate case final gate?) return gate.future;
    return savedStatus ?? DailyAttendanceStatus.unqueried(koreaDate);
  }

  @override
  Future<void> save(DailyAttendanceStatus status) async {
    if (saveError case final error?) throw error;
    savedStatus = status;
  }

  @override
  Future<void> clear() async {
    clearCallCount++;
    savedStatus = null;
  }
}

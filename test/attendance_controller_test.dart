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

  test(
    'successful callback saves display status for a new controller',
    () async {
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
    },
  );

  test(
    'a display-status save failure preserves successful server status',
    () async {
      final store = _FakeAttendanceStatusStore()
        ..saveError = StateError('full');
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
    },
  );

  test(
    'profile changes clear daily display state and persisted status',
    () async {
      final now = DateTime.utc(2026, 7, 24, 3);
      final clearStarted = Completer<void>();
      final store = _FakeAttendanceStatusStore()..clearStarted = clearStarted;
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
      await clearStarted.future;

      expect(controller.dailyStatus.queried, isFalse);
      expect(controller.dailyStatus.koreaDate, DateTime.utc(2026, 7, 24));
      expect(store.savedStatus, isNull);
      expect(store.clearCallCount, 1);
      controller.dispose();
    },
  );

  test(
    'Korean midnight clears daily display state and persisted status',
    () async {
      var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
      final clearStarted = Completer<void>();
      final store = _FakeAttendanceStatusStore()..clearStarted = clearStarted;
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
      await clearStarted.future;

      expect(controller.dailyStatus.queried, isFalse);
      expect(controller.dailyStatus.koreaDate, DateTime.utc(2026, 7, 25));
      expect(store.savedStatus, isNull);
      expect(store.clearCallCount, 1);
      controller.dispose();
    },
  );

  test(
    'a stale daily-status load cannot restore state after a profile change',
    () async {
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
    },
  );

  test(
    'a stale daily-status load cannot restore state after Korean midnight',
    () async {
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
    },
  );

  test(
    'profile reset clears a status save that was already in flight',
    () async {
      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      final clearStarted = Completer<void>();
      final store = _FakeAttendanceStatusStore()
        ..saveGate = saveGate
        ..saveStarted = saveStarted
        ..clearStarted = clearStarted;
      final controller = AttendanceController(
        profile,
        _FakeAttendanceGateway(),
        isAndroid: true,
        statusStore: store,
        now: () => DateTime.utc(2026, 7, 24, 3),
      );

      final callback = controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      await saveStarted.future;
      controller.updateProfile(
        const UserProfile(
          name: '다른 사용자',
          region: CampusRegion.pangyo5f,
          classNumber: 9,
        ),
      );
      saveGate.complete();
      await callback;
      await clearStarted.future;

      expect(store.savedStatus, isNull);
      controller.dispose();
    },
  );

  test(
    'Korean-date reset clears a status save that was already in flight',
    () async {
      var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      final clearStarted = Completer<void>();
      final store = _FakeAttendanceStatusStore()
        ..saveGate = saveGate
        ..saveStarted = saveStarted
        ..clearStarted = clearStarted;
      final controller = AttendanceController(
        profile,
        _FakeAttendanceGateway(),
        isAndroid: true,
        statusStore: store,
        now: () => now,
      );

      final callback = controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      await saveStarted.future;
      now = DateTime.utc(2026, 7, 24, 15);
      expect(controller.invalidateExpiredDailyState(), isTrue);
      saveGate.complete();
      await callback;
      await clearStarted.future;

      expect(store.savedStatus, isNull);
      controller.dispose();
    },
  );

  test('a delayed cache load cannot overwrite a newer live status', () async {
    final store = _FakeAttendanceStatusStore();
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(
      profile,
      gateway,
      isAndroid: true,
      statusStore: store,
      now: () => DateTime.utc(2026, 7, 24, 3),
    );
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    final loadGate = Completer<DailyAttendanceStatus>();
    store.loadGate = loadGate;
    final load = controller.loadDailyStatus();
    gateway.snapshot = const AttendanceSnapshot(
      networkAllowed: true,
      checkInTime: '10:00',
    );
    await controller.refreshStatus();
    loadGate.complete(
      DailyAttendanceStatus.queried(
        koreaDate: DateTime.utc(2026, 7, 24),
        fetchedAt: DateTime.utc(2026, 7, 24, 2),
        checkInTime: '08:00',
      ),
    );
    await load;

    expect(controller.dailyStatus.checkInTime, '10:00');
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

  test(
    'status refresh without a token requires authentication without IO',
    () async {
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );

      final result = await controller.requestStatusRefresh();

      expect(result, AttendanceRequestResult.authenticationRequired);
      expect(gateway.validationCallCount, 0);
      expect(gateway.fetchCallCount, 0);
      expect(gateway.recordCallCount, 0);
      expect(gateway.authenticationCallCount, 0);
      controller.dispose();
    },
  );

  test('refresh authentication callback only fetches current status', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);

    expect(
      await controller.requestStatusRefresh(),
      AttendanceRequestResult.authenticationRequired,
    );
    await controller.startAuthentication();
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    expect(gateway.fetchCallCount, 1);
    expect(gateway.recordCallCount, 0);
    expect(controller.readyAction, isNull);
    expect(controller.readyActionRevision, 0);
    expect(controller.completionRevision, 0);
    expect(controller.lastCompletedAction, isNull);
    controller.dispose();
  });

  test(
    'an awaited authentication callback keeps the original intent exclusive',
    () async {
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );

      expect(
        await controller.requestAction(AttendanceAction.leave),
        AttendanceRequestResult.authenticationRequired,
      );
      await controller.startAuthentication();

      expect(controller.awaitingAuthenticationCallback, isTrue);
      expect(
        await controller.requestStatusRefresh(),
        AttendanceRequestResult.completed,
      );
      expect(
        await controller.requestAction(AttendanceAction.checkOut),
        AttendanceRequestResult.completed,
      );
      await controller.startAuthentication();
      expect(gateway.authenticationCallCount, 1);

      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      expect(controller.awaitingAuthenticationCallback, isFalse);
      expect(controller.readyAction, AttendanceAction.leave);
      expect(gateway.fetchCallCount, 1);
      controller.dispose();
    },
  );

  test(
    'callback error clears waiting state but preserves retry intent',
    () async {
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );

      await controller.requestAction(AttendanceAction.leave);
      await controller.startAuthentication();
      expect(controller.awaitingAuthenticationCallback, isTrue);

      await controller.handleCallback(Uri.parse('https://att.skala-ai.com/'));

      expect(controller.awaitingAuthenticationCallback, isFalse);
      expect(controller.retryRequiresAuthentication, isTrue);

      await controller.startAuthentication();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      expect(gateway.authenticationCallCount, 2);
      expect(controller.readyAction, AttendanceAction.leave);
      controller.dispose();
    },
  );

  test('pending cancellation clears callback waiting state', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);

    await controller.requestAction(AttendanceAction.leave);
    await controller.startAuthentication();
    expect(controller.awaitingAuthenticationCallback, isTrue);

    controller.cancelPendingRequest();

    expect(controller.awaitingAuthenticationCallback, isFalse);
    expect(
      await controller.requestStatusRefresh(),
      AttendanceRequestResult.authenticationRequired,
    );
    controller.dispose();
  });

  test(
    'canceling an in-flight browser launch cannot restore waiting state',
    () async {
      final authenticationGate = Completer<void>();
      final gateway = _FakeAttendanceGateway()
        ..authenticationGate = authenticationGate;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.requestAction(AttendanceAction.leave);

      final authentication = controller.startAuthentication();
      await Future<void>.delayed(Duration.zero);
      expect(controller.busy, isTrue);

      controller.cancelPendingRequest();
      authenticationGate.complete();
      await authentication;

      expect(controller.awaitingAuthenticationCallback, isFalse);
      expect(controller.busy, isFalse);
      controller.dispose();
    },
  );

  test(
    'disposing an in-flight browser launch invalidates its result',
    () async {
      final authenticationGate = Completer<void>();
      final gateway = _FakeAttendanceGateway()
        ..authenticationGate = authenticationGate;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.requestStatusRefresh();

      final authentication = controller.startAuthentication();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();

      authenticationGate.complete();
      await authentication;

      expect(controller.awaitingAuthenticationCallback, isFalse);
    },
  );

  test(
    'tokenless callback invalidates an in-flight launch and preserves intent',
    () async {
      final authenticationGate = Completer<void>();
      final gateway = _FakeAttendanceGateway()
        ..authenticationGate = authenticationGate;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.requestAction(AttendanceAction.leave);

      final authentication = controller.startAuthentication();
      await Future<void>.delayed(Duration.zero);
      await controller.handleCallback(Uri.parse('https://att.skala-ai.com/'));

      expect(controller.awaitingAuthenticationCallback, isFalse);
      expect(controller.busy, isFalse);
      expect(controller.retryRequiresAuthentication, isTrue);

      authenticationGate.complete();
      await authentication;
      expect(controller.awaitingAuthenticationCallback, isFalse);

      await controller.startAuthentication();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      expect(gateway.authenticationCallCount, 2);
      expect(controller.readyAction, AttendanceAction.leave);
      controller.dispose();
    },
  );

  test(
    'link stream error invalidates an in-flight launch and preserves intent',
    () async {
      final authenticationGate = Completer<void>();
      final gateway = _FakeAttendanceGateway()
        ..authenticationGate = authenticationGate;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.requestAction(AttendanceAction.leave);

      final authentication = controller.startAuthentication();
      await Future<void>.delayed(Duration.zero);
      controller.reportLinkError(StateError('link failed'));

      expect(controller.awaitingAuthenticationCallback, isFalse);
      expect(controller.busy, isFalse);
      expect(controller.retryRequiresAuthentication, isTrue);

      authenticationGate.complete();
      await authentication;
      expect(controller.awaitingAuthenticationCallback, isFalse);

      await controller.startAuthentication();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      expect(gateway.authenticationCallCount, 2);
      expect(controller.readyAction, AttendanceAction.leave);
      controller.dispose();
    },
  );

  test('status refresh reuses a valid in-memory token', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );
    gateway.snapshot = const AttendanceSnapshot(
      networkAllowed: true,
      checkInTime: '10:00',
    );

    final result = await controller.requestStatusRefresh();

    expect(result, AttendanceRequestResult.completed);
    expect(gateway.validationCallCount, 2);
    expect(gateway.fetchCallCount, 2);
    expect(gateway.authenticationCallCount, 0);
    expect(gateway.recordCallCount, 0);
    expect(controller.snapshot?.checkInTime, '10:00');
    expect(controller.readyAction, isNull);
    controller.dispose();
  });

  test(
    'action request without a token becomes ready once after callback',
    () async {
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );

      expect(
        await controller.requestAction(AttendanceAction.leave),
        AttendanceRequestResult.authenticationRequired,
      );
      expect(gateway.fetchCallCount, 0);
      expect(gateway.recordCallCount, 0);

      await controller.startAuthentication();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      expect(gateway.fetchCallCount, 1);
      expect(gateway.recordCallCount, 0);
      expect(controller.readyAction, AttendanceAction.leave);
      expect(controller.readyActionRevision, 1);
      expect(controller.completionRevision, 0);
      controller.dispose();
    },
  );

  test(
    'action request with a valid token live-fetches before becoming ready',
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

      final result = await controller.requestAction(AttendanceAction.leave);

      expect(result, AttendanceRequestResult.completed);
      expect(gateway.validationCallCount, 2);
      expect(gateway.fetchCallCount, 2);
      expect(gateway.recordCallCount, 0);
      expect(controller.readyAction, AttendanceAction.leave);
      expect(controller.readyActionRevision, 1);
      controller.dispose();
    },
  );

  test(
    'action request uses the live snapshot to reject unavailable actions',
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
      gateway.snapshot = const AttendanceSnapshot(
        networkAllowed: true,
        checkInTime: '09:00',
        checkOutTime: '18:00',
      );

      final result = await controller.requestAction(AttendanceAction.leave);

      expect(result, AttendanceRequestResult.completed);
      expect(gateway.fetchCallCount, 2);
      expect(gateway.recordCallCount, 0);
      expect(controller.snapshot?.checkOutTime, '18:00');
      expect(controller.readyAction, isNull);
      expect(controller.message, contains('현재 출결 상태에서는'));
      controller.dispose();
    },
  );

  test(
    'local token validation failure retains action intent for authentication',
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
      gateway.validationError = const FormatException('expired');

      expect(
        await controller.requestAction(AttendanceAction.leave),
        AttendanceRequestResult.authenticationRequired,
      );
      expect(gateway.fetchCallCount, 1);
      expect(controller.authenticated, isFalse);

      gateway.validationError = null;
      await controller.startAuthentication();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=new-token'),
      );

      expect(controller.readyAction, AttendanceAction.leave);
      expect(controller.readyActionRevision, 1);
      expect(gateway.recordCallCount, 0);
      controller.dispose();
    },
  );

  test(
    'server authentication expiry retains refresh intent for authentication',
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
      gateway.fetchError = const AttendanceAuthenticationExpiredException();

      expect(
        await controller.requestStatusRefresh(),
        AttendanceRequestResult.authenticationRequired,
      );
      expect(controller.authenticated, isFalse);
      expect(gateway.recordCallCount, 0);

      gateway.fetchError = null;
      await controller.startAuthentication();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=new-token'),
      );

      expect(controller.snapshot, same(gateway.snapshot));
      expect(controller.readyAction, isNull);
      expect(controller.readyActionRevision, 0);
      expect(gateway.recordCallCount, 0);
      controller.dispose();
    },
  );

  test(
    'callback grace recovery tap reauthenticates without replacing action intent',
    () async {
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      expect(
        await controller.requestAction(AttendanceAction.leave),
        AttendanceRequestResult.authenticationRequired,
      );
      await controller.startAuthentication();
      controller.startAuthenticationCallbackGrace(duration: Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        await controller.requestStatusRefresh(),
        AttendanceRequestResult.authenticationRequired,
      );
      await controller.startAuthentication();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      expect(gateway.authenticationCallCount, 2);
      expect(controller.readyAction, AttendanceAction.leave);
      expect(gateway.recordCallCount, 0);
      controller.dispose();
    },
  );

  test('cancelPendingRequest drops only the not-yet-executed intent', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);

    await controller.requestAction(AttendanceAction.leave);
    controller.cancelPendingRequest();
    await controller.startAuthentication();
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    expect(controller.readyAction, isNull);
    expect(controller.readyActionRevision, 0);
    expect(gateway.recordCallCount, 0);
    controller.dispose();
  });

  test(
    'cancelPendingRequest invalidates an in-flight token-reuse preparation',
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
      final fetchGate = Completer<void>();
      gateway.fetchGate = fetchGate;

      final request = controller.requestAction(AttendanceAction.leave);
      await Future<void>.delayed(Duration.zero);
      expect(controller.busy, isTrue);

      controller.cancelPendingRequest();

      expect(controller.busy, isFalse);
      fetchGate.complete();
      expect(await request, AttendanceRequestResult.completed);
      expect(controller.readyAction, isNull);
      expect(controller.readyActionRevision, 0);
      expect(controller.statusRevision, 1);
      expect(gateway.recordCallCount, 0);
      controller.dispose();
    },
  );

  test(
    'ready action can be cancelled without clearing the live session',
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
      await controller.requestAction(AttendanceAction.leave);

      controller.cancelReadyAction();

      expect(controller.readyAction, isNull);
      expect(controller.authenticated, isTrue);
      expect(controller.snapshot, isNotNull);
      controller.dispose();
    },
  );

  test('performAction clears the ready event before sending', () async {
    final recordGate = Completer<void>();
    final gateway = _FakeAttendanceGateway()..recordGate = recordGate;
    final controller = AttendanceController(profile, gateway, isAndroid: true);
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );
    await controller.requestAction(AttendanceAction.leave);
    final readyRevision = controller.readyActionRevision;

    final action = controller.performAction(
      AttendanceAction.leave,
      readyActionRevision: readyRevision,
    );
    expect(controller.readyAction, isNull);
    recordGate.complete();
    await action;

    expect(gateway.recordCallCount, 1);
    controller.dispose();
  });

  test(
    'an old ready revision cannot send a newly prepared same action',
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
      await controller.requestAction(AttendanceAction.leave);
      final oldRevision = controller.readyActionRevision;
      await controller.requestAction(AttendanceAction.leave);
      final currentRevision = controller.readyActionRevision;

      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: oldRevision,
      );

      expect(currentRevision, greaterThan(oldRevision));
      expect(gateway.recordCallCount, 0);
      expect(controller.readyAction, AttendanceAction.leave);
      expect(controller.readyActionRevision, currentRevision);
      controller.dispose();
    },
  );

  test(
    'token-reused scheduled action request remembers its occurrence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now();
      final scheduledAt = now.subtract(const Duration(minutes: 1));
      final schedule = AttendanceSchedule(
        id: 'reused-token-leave',
        action: AttendanceAction.leave,
        hour: scheduledAt.hour,
        minute: scheduledAt.minute,
        weekdays: {scheduledAt.weekday},
        enabled: true,
      );
      final store = AttendanceCompletionStore();
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        completionStore: store,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );

      await controller.requestAction(
        AttendanceAction.leave,
        scheduleId: schedule.id,
        scheduledAt: scheduledAt,
      );

      final restored = AttendanceController(
        profile,
        _FakeAttendanceGateway(),
        completionStore: store,
      );
      await restored.loadCompletionHistory(now: now);
      expect(restored.wasScheduleCompleted(schedule, now), isTrue);
      expect(gateway.authenticationCallCount, 0);
      expect(gateway.recordCallCount, 0);
      controller.dispose();
      restored.dispose();
    },
  );

  test(
    'invalid reused token does not complete a scheduled occurrence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now();
      final scheduledAt = now.subtract(const Duration(minutes: 1));
      final schedule = AttendanceSchedule(
        id: 'expired-token-leave',
        action: AttendanceAction.leave,
        hour: scheduledAt.hour,
        minute: scheduledAt.minute,
        weekdays: {scheduledAt.weekday},
        enabled: true,
      );
      final store = AttendanceCompletionStore();
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        completionStore: store,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      gateway.validationError = const FormatException('expired');

      expect(
        await controller.requestAction(
          AttendanceAction.leave,
          scheduleId: schedule.id,
          scheduledAt: scheduledAt,
        ),
        AttendanceRequestResult.authenticationRequired,
      );

      final restored = AttendanceController(
        profile,
        _FakeAttendanceGateway(),
        completionStore: store,
      );
      await restored.loadCompletionHistory(now: now);
      expect(restored.wasScheduleCompleted(schedule, now), isFalse);
      controller.dispose();
      restored.dispose();
    },
  );

  test(
    'scheduled action metadata is not completed before authentication starts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now();
      final scheduledAt = now.subtract(const Duration(minutes: 1));
      final schedule = AttendanceSchedule(
        id: 'pending-auth-leave',
        action: AttendanceAction.leave,
        hour: scheduledAt.hour,
        minute: scheduledAt.minute,
        weekdays: {scheduledAt.weekday},
        enabled: true,
      );
      final store = AttendanceCompletionStore();
      final controller = AttendanceController(
        profile,
        _FakeAttendanceGateway(),
        isAndroid: true,
        completionStore: store,
      );

      expect(
        await controller.requestAction(
          AttendanceAction.leave,
          scheduleId: schedule.id,
          scheduledAt: scheduledAt,
        ),
        AttendanceRequestResult.authenticationRequired,
      );

      final restored = AttendanceController(
        profile,
        _FakeAttendanceGateway(),
        completionStore: store,
      );
      await restored.loadCompletionHistory(now: now);
      expect(restored.wasScheduleCompleted(schedule, now), isFalse);
      controller.dispose();
      restored.dispose();
    },
  );

  test(
    'failed browser launch does not complete a scheduled occurrence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now();
      final scheduledAt = now.subtract(const Duration(minutes: 1));
      final schedule = AttendanceSchedule(
        id: 'failed-auth-leave',
        action: AttendanceAction.leave,
        hour: scheduledAt.hour,
        minute: scheduledAt.minute,
        weekdays: {scheduledAt.weekday},
        enabled: true,
      );
      final store = AttendanceCompletionStore();
      final gateway = _FakeAttendanceGateway()
        ..authenticationError = TimeoutException('launch failed');
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        completionStore: store,
      );
      await controller.requestAction(
        AttendanceAction.leave,
        scheduleId: schedule.id,
        scheduledAt: scheduledAt,
      );

      await controller.startAuthentication();

      final restored = AttendanceController(
        profile,
        _FakeAttendanceGateway(),
        completionStore: store,
      );
      await restored.loadCompletionHistory(now: now);
      expect(restored.wasScheduleCompleted(schedule, now), isFalse);
      expect(controller.retryRequiresAuthentication, isTrue);
      controller.dispose();
      restored.dispose();
    },
  );

  test('profile change clears pending and ready action state', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);
    await controller.requestAction(AttendanceAction.leave);
    await controller.startAuthentication();
    expect(controller.awaitingAuthenticationCallback, isTrue);

    controller.updateProfile(
      const UserProfile(
        name: '다른 사용자',
        region: CampusRegion.pangyo5f,
        classNumber: 9,
      ),
    );
    expect(controller.awaitingAuthenticationCallback, isFalse);
    await controller.startAuthentication();
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );

    expect(controller.readyAction, isNull);
    await controller.requestAction(AttendanceAction.leave);
    expect(controller.readyAction, AttendanceAction.leave);

    controller.updateProfile(profile);

    expect(controller.readyAction, isNull);
    expect(controller.authenticated, isFalse);
    controller.dispose();
  });

  test(
    'Korean date change clears intent and blocks an older callback result',
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
      await controller.requestAction(AttendanceAction.leave);
      await controller.startAuthentication();
      expect(controller.awaitingAuthenticationCallback, isTrue);
      final callback = controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      await Future<void>.delayed(Duration.zero);

      now = DateTime.utc(2026, 7, 24, 15, 0, 1);
      expect(controller.invalidateExpiredDailyState(), isTrue);
      expect(controller.awaitingAuthenticationCallback, isFalse);
      fetchGate.complete();
      await callback;

      expect(controller.authenticated, isFalse);
      expect(controller.snapshot, isNull);
      expect(controller.readyAction, isNull);
      expect(controller.readyActionRevision, 0);
      controller.dispose();
    },
  );

  test(
    'Korean date change clears an awaited authentication callback',
    () async {
      var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
      final gateway = _FakeAttendanceGateway();
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        now: () => now,
      );
      await controller.requestAction(AttendanceAction.leave);
      await controller.startAuthentication();
      expect(controller.awaitingAuthenticationCallback, isTrue);

      now = DateTime.utc(2026, 7, 24, 15, 0, 1);
      expect(controller.invalidateExpiredDailyState(), isTrue);

      expect(controller.awaitingAuthenticationCallback, isFalse);
      expect(
        await controller.requestStatusRefresh(),
        AttendanceRequestResult.authenticationRequired,
      );
      controller.dispose();
    },
  );

  test('a newer action intent supersedes an in-flight callback', () async {
    final fetchGate = Completer<void>();
    final gateway = _FakeAttendanceGateway()..fetchGate = fetchGate;
    final controller = AttendanceController(profile, gateway, isAndroid: true);
    await controller.requestAction(AttendanceAction.leave);
    final oldCallback = controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=old-token'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      await controller.requestAction(AttendanceAction.checkOut),
      AttendanceRequestResult.authenticationRequired,
    );
    expect(controller.busy, isFalse);
    fetchGate.complete();
    await oldCallback;

    expect(controller.authenticated, isFalse);
    expect(controller.snapshot, isNull);
    expect(controller.readyAction, isNull);

    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=new-token'),
    );
    expect(controller.readyAction, AttendanceAction.checkOut);
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
    expect(controller.message, '우측 상단 새로고침 버튼을 눌러 Google 인증 후 출결 정보를 갱신하세요.');
    controller.dispose();
  });

  test('records an allowed action and refreshes server state', () async {
    final gateway = _FakeAttendanceGateway();
    final controller = AttendanceController(profile, gateway, isAndroid: true);
    await controller.handleCallback(
      Uri.parse('https://att.skala-ai.com/?token=test-token'),
    );
    final readyRevision = await _prepareAction(
      controller,
      AttendanceAction.leave,
    );

    await controller.performAction(
      AttendanceAction.leave,
      readyActionRevision: readyRevision,
    );

    expect(gateway.recordedAction, AttendanceAction.leave);
    expect(gateway.recordedToken, 'test-token');
    expect(controller.snapshot?.earlyLeaveTime, '12:00');
    expect(controller.message, '외출 처리가 완료되었습니다.');
    expect(controller.statusRevision, 3);
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

    await controller.performAction(
      AttendanceAction.checkIn,
      readyActionRevision: controller.readyActionRevision,
    );

    expect(gateway.recordedAction, isNull);
    expect(controller.message, contains('다시 확인'));
    controller.dispose();
  });

  test('authentication timeout exposes a friendly retry action', () async {
    final gateway = _FakeAttendanceGateway()
      ..authenticationError = TimeoutException('timed out');
    final controller = AttendanceController(profile, gateway, isAndroid: true);

    await controller.startAuthentication();

    expect(controller.awaitingAuthenticationCallback, isFalse);
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
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );
      gateway.fetchError = TimeoutException('timed out');

      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );

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
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );
      gateway
        ..fetchError = TimeoutException('timed out')
        ..reflectRecordedAction = false;

      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );

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
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );

      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );

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
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );

      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );

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
    'POST authentication expiry reauthenticates without resending the action',
    () async {
      final gateway = _FakeAttendanceGateway()
        ..recordError = const AttendanceAuthenticationExpiredException()
        ..reflectRecordedAction = false;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );

      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );

      expect(controller.authenticated, isFalse);
      expect(controller.retryRequiresAuthentication, isTrue);
      expect(gateway.recordCallCount, 1);

      gateway.recordError = null;
      expect(
        await controller.requestAction(AttendanceAction.checkOut),
        AttendanceRequestResult.authenticationRequired,
      );
      await controller.startAuthentication();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=new-token'),
      );

      expect(gateway.recordCallCount, 1);
      expect(controller.readyAction, isNull);
      expect(controller.completionRevision, 0);
      controller.dispose();
    },
  );

  test(
    'verification authentication expiry reconciles after reauth without resend',
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
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );
      gateway.fetchError = const AttendanceAuthenticationExpiredException();

      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );

      expect(controller.authenticated, isFalse);
      expect(controller.retryRequiresAuthentication, isTrue);
      expect(gateway.recordCallCount, 1);
      expect(controller.completionRevision, 0);

      gateway.fetchError = null;
      expect(
        await controller.requestAction(AttendanceAction.checkOut),
        AttendanceRequestResult.authenticationRequired,
      );
      await controller.startAuthentication();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=new-token'),
      );

      expect(gateway.recordCallCount, 1);
      expect(controller.readyAction, isNull);
      expect(controller.completionRevision, 1);
      expect(controller.lastCompletedAction, AttendanceAction.leave);
      controller.dispose();
    },
  );

  test(
    'refresh authentication expiry preserves uncertain action for reconciliation',
    () async {
      final gateway = _FakeAttendanceGateway()
        ..recordError = TimeoutException('timed out')
        ..reflectRecordedAction = false;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );
      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );
      gateway
        ..recordError = null
        ..fetchError = const AttendanceAuthenticationExpiredException();

      await controller.refreshStatus();

      expect(controller.authenticated, isFalse);
      expect(controller.retryRequiresAuthentication, isTrue);
      expect(gateway.recordCallCount, 1);

      gateway.fetchError = null;
      await controller.retry();
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=new-token'),
      );

      expect(gateway.recordCallCount, 1);
      expect(controller.readyAction, isNull);
      expect(controller.completionRevision, 0);
      expect(controller.retryLabel, '출결 상태 다시 조회');
      controller.dispose();
    },
  );

  test(
    'an uncertain action tap only reconciles status and cannot become ready again',
    () async {
      final gateway = _FakeAttendanceGateway()
        ..recordError = TimeoutException('timed out')
        ..reflectRecordedAction = false;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );
      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );
      final fetchesBeforeSecondTap = gateway.fetchCallCount;

      await controller.requestAction(AttendanceAction.leave);

      expect(gateway.recordCallCount, 1);
      expect(gateway.fetchCallCount, fetchesBeforeSecondTap + 1);
      expect(controller.readyAction, isNull);
      expect(controller.completionRevision, 0);
      expect(controller.canRetry, isTrue);
      expect(controller.retryLabel, '출결 상태 다시 조회');
      controller.dispose();
    },
  );

  test(
    'header refresh completes an uncertain action only when status reflects it',
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
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );
      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );
      final fetchesBeforeRefresh = gateway.fetchCallCount;

      await controller.requestStatusRefresh();

      expect(gateway.recordCallCount, 1);
      expect(gateway.fetchCallCount, fetchesBeforeRefresh + 1);
      expect(controller.readyAction, isNull);
      expect(controller.completionRevision, 1);
      expect(controller.lastCompletedAction, AttendanceAction.leave);
      controller.dispose();
    },
  );

  test(
    'profile reset wins over a gated uncertain-action reconciliation',
    () async {
      final store = _FakeAttendanceStatusStore();
      final gateway = _FakeAttendanceGateway()
        ..recordError = TimeoutException('timed out')
        ..reflectRecordedAction = false;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        statusStore: store,
        now: () => DateTime.utc(2026, 7, 24, 3),
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );
      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );
      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      store
        ..saveGate = saveGate
        ..saveStarted = saveStarted;

      final refresh = controller.refreshStatus();
      await saveStarted.future;
      controller.updateProfile(
        const UserProfile(
          name: '다른 사용자',
          region: CampusRegion.pangyo5f,
          classNumber: 9,
        ),
      );
      saveGate.complete();
      await refresh;

      expect(controller.message, '사용자 정보가 변경되었습니다. 다시 인증해주세요.');
      expect(controller.retryRequiresAuthentication, isTrue);
      expect(controller.snapshot, isNull);
      controller.dispose();
    },
  );

  test(
    'date reset wins over a gated uncertain-action reconciliation',
    () async {
      var now = DateTime.utc(2026, 7, 24, 14, 59, 59);
      final store = _FakeAttendanceStatusStore();
      final gateway = _FakeAttendanceGateway()
        ..recordError = TimeoutException('timed out')
        ..reflectRecordedAction = false;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        statusStore: store,
        now: () => now,
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );
      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );
      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      store
        ..saveGate = saveGate
        ..saveStarted = saveStarted;

      final refresh = controller.refreshStatus();
      await saveStarted.future;
      now = DateTime.utc(2026, 7, 24, 15, 0, 1);
      expect(controller.invalidateExpiredDailyState(), isTrue);
      saveGate.complete();
      await refresh;

      expect(controller.message, '날짜가 바뀌어 오늘 출결 정보를 다시 확인해야 합니다.');
      expect(controller.retryRequiresAuthentication, isTrue);
      expect(controller.snapshot, isNull);
      controller.dispose();
    },
  );

  test(
    'dispose cancels a gated uncertain-action reconciliation continuation',
    () async {
      final store = _FakeAttendanceStatusStore();
      final gateway = _FakeAttendanceGateway()
        ..recordError = TimeoutException('timed out')
        ..reflectRecordedAction = false;
      final controller = AttendanceController(
        profile,
        gateway,
        isAndroid: true,
        statusStore: store,
        now: () => DateTime.utc(2026, 7, 24, 3),
      );
      await controller.handleCallback(
        Uri.parse('https://att.skala-ai.com/?token=test-token'),
      );
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );
      await controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );
      final saveGate = Completer<void>();
      final saveStarted = Completer<void>();
      store
        ..saveGate = saveGate
        ..saveStarted = saveStarted;

      final refresh = controller.refreshStatus();
      await saveStarted.future;
      controller.dispose();
      saveGate.complete();

      await expectLater(refresh, completes);
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
      final readyRevision = await _prepareAction(
        controller,
        AttendanceAction.leave,
      );

      final action = controller.performAction(
        AttendanceAction.leave,
        readyActionRevision: readyRevision,
      );
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

Future<int> _prepareAction(
  AttendanceController controller,
  AttendanceAction action,
) async {
  expect(
    await controller.requestAction(action),
    AttendanceRequestResult.completed,
  );
  expect(controller.readyAction, action);
  return controller.readyActionRevision;
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
  Object? validationError;
  Object? fetchError;
  Object? recordError;
  Completer<void>? authenticationGate;
  Completer<void>? fetchGate;
  Completer<void>? recordGate;
  bool reflectRecordedAction = true;
  int recordCallCount = 0;
  int authenticationCallCount = 0;
  int validationCallCount = 0;
  int fetchCallCount = 0;

  @override
  Future<void> startBrowserAuthentication(UserProfile profile) async {
    authenticationCallCount++;
    await authenticationGate?.future;
    if (authenticationError case final error?) throw error;
    authenticationProfile = profile;
  }

  @override
  void validateAttendanceToken(String token, UserProfile profile) {
    validationCallCount++;
    if (validationError case final error?) throw error;
    validatedToken = token;
  }

  @override
  Future<AttendanceSnapshot> fetchToday(String token) async {
    fetchCallCount++;
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
  Completer<void>? saveGate;
  Completer<void>? saveStarted;
  Completer<void>? clearStarted;
  int clearCallCount = 0;

  @override
  Future<DailyAttendanceStatus> loadFor(DateTime koreaDate) async {
    if (loadGate case final gate?) return gate.future;
    return savedStatus ?? DailyAttendanceStatus.unqueried(koreaDate);
  }

  @override
  Future<void> save(DailyAttendanceStatus status) async {
    final started = saveStarted;
    if (started != null && !started.isCompleted) started.complete();
    await saveGate?.future;
    if (saveError case final error?) throw error;
    savedStatus = status;
  }

  @override
  Future<void> clear() async {
    final started = clearStarted;
    if (started != null && !started.isCompleted) started.complete();
    clearCallCount++;
    savedStatus = null;
  }
}

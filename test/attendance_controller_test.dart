import 'package:flutter_test/flutter_test.dart';
import 'package:skala_attendance/features/attendance/application/attendance_controller.dart';
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
    controller.dispose();
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

  @override
  Future<void> startBrowserAuthentication(UserProfile profile) async {
    authenticationProfile = profile;
  }

  @override
  void validateAttendanceToken(String token, UserProfile profile) {
    validatedToken = token;
  }

  @override
  Future<AttendanceSnapshot> fetchToday(String token) async {
    fetchedToken = token;
    return snapshot;
  }

  @override
  Future<void> recordAction(String token, AttendanceAction action) async {
    recordedToken = token;
    recordedAction = action;
    if (action == AttendanceAction.leave) {
      snapshot = const AttendanceSnapshot(
        networkAllowed: true,
        checkInTime: '09:00',
        earlyLeaveTime: '12:00',
      );
    }
  }

  @override
  void close() {}
}

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/app/app.dart';
import 'package:skala_attendance/features/attendance/data/attendance_gateway.dart';
import 'package:skala_attendance/features/attendance/domain/attendance_snapshot.dart';
import 'package:skala_attendance/features/attendance/presentation/attendance_screen.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';
import 'package:skala_attendance/features/profile/presentation/profile_setup_screen.dart';
import 'package:skala_attendance/features/schedule/application/notification_scheduler.dart';
import 'package:skala_attendance/features/schedule/application/schedule_controller.dart';
import 'package:skala_attendance/features/schedule/data/schedule_store.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';
import 'package:skala_attendance/features/schedule/presentation/schedule_edit_screen.dart';

void main() {
  test('campus regions expose only their valid classes', () {
    expect(CampusRegion.pangyo4f.classNumbers, [1, 2, 3, 4, 5]);
    expect(CampusRegion.pangyo5f.classNumbers, [6, 7, 8, 9, 10]);
  });

  testWidgets('first launch asks for user information', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSetupScreen(onInitialSave: (_) async {})),
    );

    expect(find.text('사용자 정보 설정'), findsOneWidget);
    expect(find.text('이름'), findsOneWidget);
    expect(find.text('지역'), findsOneWidget);
    expect(find.text('반'), findsOneWidget);
    expect(find.text('저장'), findsOneWidget);
  });

  testWidgets('selecting 5F offers classes 6 through 10', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSetupScreen(onInitialSave: (_) async {})),
    );

    await tester.tap(find.text('지역'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('판교캠퍼스 5F').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('반'));
    await tester.pumpAndSettle();

    for (var number = 6; number <= 10; number++) {
      expect(find.text('$number반'), findsOneWidget);
    }
    expect(find.text('5반'), findsNothing);
  });

  testWidgets('saved user can open the profile editing screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
    });
    await tester.pumpWidget(
      SkalaAttendanceApp(notificationScheduler: _NoOpNotificationScheduler()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('사용자 정보 변경'));
    await tester.pumpAndSettle();

    expect(find.text('사용자 정보 수정'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '윤동현'), findsOneWidget);
  });

  testWidgets('schedule editor switches between weekly and one-time modes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));

    expect(find.text('공휴일 제외'), findsOneWidget);
    await tester.tap(find.text('날짜 지정'));
    await tester.pumpAndSettle();

    expect(find.text('실행 날짜'), findsOneWidget);
    expect(find.text('공휴일 제외'), findsNothing);
  });

  testWidgets('weekly editor shows holidays matching selected weekdays', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));

    await tester.tap(find.text('제외되는 공휴일 보기'));
    await tester.pumpAndSettle();

    expect(find.text('제외되는 공휴일'), findsOneWidget);
    expect(
      find.text('평일 일정과 겹치는 공휴일입니다(2026.07.14~2026.12.18 기준)'),
      findsOneWidget,
    );
    expect(find.text('제헌절'), findsOneWidget);
    expect(find.text('대체공휴일(광복절)'), findsOneWidget);
    expect(find.text('광복절'), findsNothing);
  });

  testWidgets('time picker supports AM/PM wheels and tap-to-type input', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));

    await tester.scrollUntilVisible(find.text('오전 9:00'), 300);
    await tester.tap(find.text('오전 9:00'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    expect(find.text('실행 시각 선택'), findsOneWidget);
    expect(find.text('선택'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.byKey(const Key('hour-wheel')));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPicker), findsOneWidget);
    expect(find.text('시각 직접 입력'), findsNothing);
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.at(0), '13');
    await tester.enterText(fields.at(1), '60');
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    expect(find.text('1~12 입력'), findsOneWidget);
    expect(find.text('0~59 입력'), findsOneWidget);

    await tester.enterText(fields.at(0), '5');
    await tester.enterText(fields.at(1), '50');
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    expect(find.text('오전 5:50'), findsOneWidget);
  });

  testWidgets('hour wheel crossing noon changes AM to PM', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));

    await tester.scrollUntilVisible(find.text('오전 9:00'), 300);
    await tester.tap(find.text('오전 9:00'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('hour-wheel')),
      const Offset(0, -156),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();

    expect(find.text('오후 12:00'), findsOneWidget);
  });

  testWidgets('dismissing the keyboard returns to the time wheels', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));

    await tester.scrollUntilVisible(find.text('오전 9:00'), 300);
    await tester.tap(find.text('오전 9:00'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('hour-wheel')),
      const Offset(0, -52),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hour-wheel')));
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(find.byType(TextFormField), findsNWidgets(2));

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    var hourPicker = tester.widget<CupertinoPicker>(
      find.descendant(
        of: find.byKey(const Key('hour-wheel')),
        matching: find.byType(CupertinoPicker),
      ),
    );
    expect(hourPicker.scrollController!.selectedItem % 24, 10);

    await tester.tap(find.byKey(const Key('hour-wheel')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('hour-input')), '12');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();

    hourPicker = tester.widget<CupertinoPicker>(
      find.descendant(
        of: find.byKey(const Key('hour-wheel')),
        matching: find.byType(CupertinoPicker),
      ),
    );
    expect(hourPicker.scrollController!.selectedItem % 24, 0);
  });

  testWidgets('tapping a schedule notification starts authentication', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final notifications = _NoOpNotificationScheduler()
      ..emit('{"scheduleId":"check-in","action":"checkIn"}');
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final gateway = _WidgetTestAttendanceGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: notifications,
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(gateway.authenticationProfile, profile);
    expect(notifications.tapPayload.value, isNull);
    schedules.dispose();
  });

  testWidgets('authentication callback confirms a scheduled leave action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final notifications = _NoOpNotificationScheduler()
      ..emit('{"scheduleId":"leave","action":"leave"}');
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: notifications,
          onEditProfile: () async {},
          gateway: _WidgetTestAttendanceGateway(
            snapshot: const AttendanceSnapshot(
              networkAllowed: true,
              checkInTime: '09:00',
            ),
          ),
          appLinkStream: links.stream,
          isAndroid: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('외출 처리'), findsOneWidget);
    expect(find.text('외출 전송'), findsOneWidget);

    await links.close();
    schedules.dispose();
  });
}

class _NoOpNotificationScheduler implements NotificationScheduler {
  final _tapPayload = ValueNotifier<String?>(null);

  @override
  ValueListenable<String?> get tapPayload => _tapPayload;

  @override
  Future<bool> arePermissionsGranted() async => true;

  @override
  void consumeTap() => _tapPayload.value = null;

  void emit(String payload) => _tapPayload.value = payload;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now}) async =>
      0;
}

class _WidgetTestAttendanceGateway implements AttendanceGateway {
  _WidgetTestAttendanceGateway({
    this.snapshot = const AttendanceSnapshot(networkAllowed: true),
  });

  final AttendanceSnapshot snapshot;
  UserProfile? authenticationProfile;

  @override
  Future<void> startBrowserAuthentication(UserProfile profile) async {
    authenticationProfile = profile;
  }

  @override
  Future<AttendanceSnapshot> fetchToday(String token) async {
    return snapshot;
  }

  @override
  Future<void> recordAction(String token, AttendanceAction action) async {}

  @override
  void validateAttendanceToken(String token, UserProfile profile) {}

  @override
  void close() {}
}

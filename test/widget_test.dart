import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/app/app.dart';
import 'package:skala_attendance/app/initial_setup_screen.dart';
import 'package:skala_attendance/features/attendance/data/attendance_gateway.dart';
import 'package:skala_attendance/features/attendance/data/attendance_status_store.dart';
import 'package:skala_attendance/features/attendance/data/callback_link_settings.dart';
import 'package:skala_attendance/features/attendance/domain/attendance_snapshot.dart';
import 'package:skala_attendance/features/attendance/presentation/attendance_screen.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';
import 'package:skala_attendance/features/profile/domain/profile_verifier.dart';
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

  testWidgets('invalid profile is not saved and explains every field', (
    tester,
  ) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSetupScreen(
          onInitialSave: (_) async => saved = true,
          onVerify: (_) async => throw const InvalidProfileException(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '잘못된 이름');
    await tester.tap(find.text('지역'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('판교캠퍼스 5F').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('반'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8반').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(saved, isFalse);
    expect(
      find.text('등록된 수강생 정보를 찾을 수 없습니다. 이름, 캠퍼스와 반을 다시 확인해주세요.'),
      findsOneWidget,
    );
  });

  testWidgets('invalid edited profile keeps the editing screen open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSetupScreen(
          initialProfile: const UserProfile(
            name: '기존 사용자',
            region: CampusRegion.pangyo5f,
            classNumber: 8,
          ),
          onVerify: (_) async => throw const InvalidProfileException(),
        ),
      ),
    );

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('사용자 정보 수정'), findsOneWidget);
    expect(
      find.text('등록된 수강생 정보를 찾을 수 없습니다. 이름, 캠퍼스와 반을 다시 확인해주세요.'),
      findsOneWidget,
    );
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

  testWidgets('user can select and persist an app theme', (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
    });
    await tester.pumpWidget(
      SkalaAttendanceApp(notificationScheduler: _NoOpNotificationScheduler()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('테마 설정'));
    await tester.pumpAndSettle();
    expect(find.text('시스템 설정'), findsOneWidget);
    expect(find.text('라이트 모드'), findsOneWidget);
    expect(find.text('다크 모드'), findsOneWidget);

    await tester.tap(find.text('다크 모드'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('app.themeMode'), 'dark');
  });

  testWidgets('home schedules do not wait for notification initialization', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
    });
    final notifications = _DelayedInitializationNotificationScheduler();

    await tester.pumpWidget(
      SkalaAttendanceApp(notificationScheduler: notifications),
    );
    await tester.pump();
    await tester.pump();

    await tester.scrollUntilVisible(find.text('오늘 실행할 일정이 없습니다.'), 200);
    expect(find.text('오늘 실행할 일정이 없습니다.'), findsOneWidget);
    expect(notifications.initializationStarted, isFalse);
  });

  testWidgets('schedule management refreshes notification permission status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final notifications = _SetupNotificationScheduler(granted: false);
    final schedules = ScheduleController(ScheduleStore(), notifications);
    await schedules.load();
    expect(schedules.notificationsConfigured, isFalse);
    notifications.granted = true;

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: notifications,
          onEditProfile: () async {},
          gateway: _WidgetTestAttendanceGateway(),
          appLinkStream: const Stream.empty(),
          isAndroid: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('일정 관리'), 200);
    await tester.tap(find.text('일정 관리'));
    await tester.pumpAndSettle();

    expect(find.text('출결 일정 관리'), findsOneWidget);
    expect(find.text('알림 권한 설정'), findsNothing);
    schedules.dispose();
  });

  testWidgets('attendance card is visible before authentication', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: _WidgetTestAttendanceGateway(),
          appLinkStream: const Stream.empty(),
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘 출결 · 7월 24일(금)'), findsOneWidget);
    expect(find.text('확인 전'), findsNWidgets(4));
    expect(find.byTooltip('출결 상태 새로고침'), findsOneWidget);
    for (final action in AttendanceAction.values) {
      expect(find.widgetWithText(FilledButton, action.label), findsOneWidget);
    }
    expect(find.text('출결 정보 확인하기'), findsNothing);
    expect(find.text('Google 인증 시작'), findsNothing);
    expect(find.text('Google 인증 필요'), findsNothing);
    await tester.scrollUntilVisible(find.text('오늘 예정된 동작'), 200);
    expect(
      tester.getTopLeft(find.text('오늘 출결 · 7월 24일(금)')).dy,
      lessThan(tester.getTopLeft(find.text('오늘 예정된 동작')).dy),
    );
    schedules.dispose();
  });

  testWidgets('refresh authenticates and updates the same attendance card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();
    final gateway = _WidgetTestAttendanceGateway(
      snapshot: const AttendanceSnapshot(
        networkAllowed: false,
        checkInTime: '2026-07-24T00:01:23.000Z',
        checkOutTime: '2026-07-24T09:02:59.000Z',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('출결 상태 새로고침'));
    await tester.pumpAndSettle();

    expect(gateway.authenticationCallCount, 1);
    expect(gateway.recordedAction, isNull);
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();

    expect(find.text('출결 정보 확인하기'), findsNothing);
    expect(find.text('오늘 출결 · 7월 24일(금)'), findsOneWidget);
    expect(find.text('09:01'), findsOneWidget);
    expect(find.text('18:02'), findsOneWidget);
    expect(find.text('방금 업데이트됨'), findsOneWidget);
    expect(find.textContaining('네트워크 허용:'), findsNothing);
    expect(find.text('현재 네트워크에서는 출결 동작을 전송할 수 없습니다.'), findsOneWidget);
    expect(find.textContaining('2026-07-24T'), findsNothing);
    expect(gateway.recordedAction, isNull);
    expect(find.textContaining('오늘 출결 ·'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('오늘 예정된 동작'), 200);
    expect(
      tester.getTopLeft(find.text('오늘 출결 · 7월 24일(금)')).dy,
      lessThan(tester.getTopLeft(find.text('오늘 예정된 동작')).dy),
    );
    final checkIn = tester.getTopLeft(
      find.byKey(const ValueKey('attendance-status-checkIn')),
    );
    final checkOut = tester.getTopLeft(
      find.byKey(const ValueKey('attendance-status-checkOut')),
    );
    final leave = tester.getTopLeft(
      find.byKey(const ValueKey('attendance-status-leave')),
    );
    final returnFromLeave = tester.getTopLeft(
      find.byKey(const ValueKey('attendance-status-returnFromLeave')),
    );
    expect(checkIn.dy, moreOrLessEquals(checkOut.dy));
    expect(leave.dy, moreOrLessEquals(returnFromLeave.dy));
    expect(checkIn.dx, lessThan(checkOut.dx));
    expect(leave.dx, lessThan(returnFromLeave.dx));
    expect(checkIn.dy, lessThan(leave.dy));

    await links.close();
    schedules.dispose();
  });

  testWidgets('refresh reuses a valid token and never records an action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();
    final gateway = _WidgetTestAttendanceGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('출결 상태 새로고침'));
    await tester.pumpAndSettle();
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();

    expect(gateway.authenticationCallCount, 1);
    expect(gateway.fetchCallCount, 1);

    await tester.tap(find.byTooltip('출결 상태 새로고침'));
    await tester.pumpAndSettle();

    expect(gateway.authenticationCallCount, 1);
    expect(gateway.fetchCallCount, 2);
    expect(gateway.recordedAction, isNull);

    await links.close();
    schedules.dispose();
  });

  testWidgets(
    'action authenticates and records only after current confirmation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const profile = UserProfile(
        name: '윤동현',
        region: CampusRegion.pangyo5f,
        classNumber: 8,
      );
      final schedules = ScheduleController(ScheduleStore());
      await schedules.load();
      final links = StreamController<Uri>();
      final gateway = _WidgetTestAttendanceGateway(
        snapshot: const AttendanceSnapshot(
          networkAllowed: true,
          checkInTime: '09:00',
        ),
        snapshotAfterAction: const AttendanceSnapshot(
          networkAllowed: true,
          checkInTime: '09:00',
          earlyLeaveTime: '12:00',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AttendanceScreen(
            profile: profile,
            scheduleController: schedules,
            notificationScheduler: _NoOpNotificationScheduler(),
            onEditProfile: () async {},
            gateway: gateway,
            appLinkStream: links.stream,
            isAndroid: true,
            callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
            now: () => DateTime.utc(2026, 7, 24, 3),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(FilledButton, '외출'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '외출'));
      await tester.pumpAndSettle();
      expect(gateway.authenticationCallCount, 1);
      expect(gateway.recordedAction, isNull);

      links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
      await tester.pumpAndSettle();
      expect(find.text('외출 처리'), findsOneWidget);
      expect(gateway.recordedAction, isNull);

      await tester.tap(find.text('외출 전송'));
      await tester.pumpAndSettle();
      expect(gateway.recordedAction, AttendanceAction.leave);

      await links.close();
      schedules.dispose();
    },
  );

  testWidgets('action reuses a valid token and still asks for confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();
    final gateway = _WidgetTestAttendanceGateway(
      snapshot: const AttendanceSnapshot(
        networkAllowed: true,
        checkInTime: '09:00',
      ),
      snapshotAfterAction: const AttendanceSnapshot(
        networkAllowed: true,
        checkInTime: '09:00',
        earlyLeaveTime: '12:00',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('출결 상태 새로고침'));
    await tester.pumpAndSettle();
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(FilledButton, '외출'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '외출'));
    await tester.pumpAndSettle();

    expect(gateway.authenticationCallCount, 1);
    expect(gateway.fetchCallCount, 2);
    expect(find.text('외출 처리'), findsOneWidget);
    expect(gateway.recordedAction, isNull);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(gateway.recordedAction, isNull);

    await links.close();
    schedules.dispose();
  });

  testWidgets('a replaced confirmation cannot send a stale action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();
    final gateway = _WidgetTestAttendanceGateway(
      snapshot: const AttendanceSnapshot(
        networkAllowed: true,
        checkInTime: '09:00',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('출결 상태 새로고침'));
    await tester.pumpAndSettle();
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '외출'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '외출'));
    await tester.pumpAndSettle();
    expect(find.text('외출 처리'), findsOneWidget);

    final refresh = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip('출결 상태 새로고침'),
            matching: find.byType(IconButton),
          )
          .first,
    );
    refresh.onPressed!.call();
    await tester.pumpAndSettle();
    await tester.tap(find.text('외출 전송'));
    await tester.pumpAndSettle();

    expect(gateway.recordedAction, isNull);

    await links.close();
    schedules.dispose();
  });

  testWidgets('cached attendance status restores as display-only state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AttendanceStatusStore.storageKey: jsonEncode({
        'date': '2026-07-24',
        'fetchedAt': '2026-07-24T03:00:00.000Z',
        'checkInTime': '09:01',
      }),
    });
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final gateway = _WidgetTestAttendanceGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: const Stream.empty(),
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('09:01'), findsOneWidget);
    expect(find.text('없음'), findsNWidgets(3));
    expect(find.widgetWithText(FilledButton, '외출'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '퇴실'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '입실'), findsNothing);
    expect(gateway.authenticationCallCount, 0);
    expect(gateway.fetchCallCount, 0);

    schedules.dispose();
  });

  testWidgets('large accessibility text stacks attendance status tiles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: AttendanceScreen(
            profile: profile,
            scheduleController: schedules,
            notificationScheduler: _NoOpNotificationScheduler(),
            onEditProfile: () async {},
            gateway: _WidgetTestAttendanceGateway(
              snapshot: const AttendanceSnapshot(
                networkAllowed: true,
                checkInTime: '2026-07-24T00:01:23.000Z',
                checkOutTime: '2026-07-24T09:02:59.000Z',
                earlyLeaveTime: '2026-07-24T03:34:56.000Z',
                returnTime: '2026-07-24T04:45:00.000Z',
              ),
            ),
            appLinkStream: links.stream,
            isAndroid: true,
            callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
            now: () => DateTime.utc(2026, 7, 24, 3),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();

    final positions = [
      tester.getTopLeft(
        find.byKey(const ValueKey('attendance-status-checkIn')),
      ),
      tester.getTopLeft(
        find.byKey(const ValueKey('attendance-status-checkOut')),
      ),
      tester.getTopLeft(find.byKey(const ValueKey('attendance-status-leave'))),
      tester.getTopLeft(
        find.byKey(const ValueKey('attendance-status-returnFromLeave')),
      ),
    ];
    expect(positions.map((position) => position.dx).toSet(), hasLength(1));
    for (var index = 1; index < positions.length; index++) {
      expect(positions[index - 1].dy, lessThan(positions[index].dy));
    }
    expect(tester.takeException(), isNull);

    await links.close();
    schedules.dispose();
  });

  testWidgets('attendance status tiles adapt to phone width', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: _WidgetTestAttendanceGateway(
            snapshot: const AttendanceSnapshot(
              networkAllowed: true,
              checkInTime: '2026-07-24T00:01:23.000Z',
              checkOutTime: '2026-07-24T09:02:59.000Z',
              earlyLeaveTime: '2026-07-24T03:34:56.000Z',
              returnTime: '2026-07-24T04:45:00.000Z',
            ),
          ),
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();

    Offset tilePosition(AttendanceAction action) => tester.getTopLeft(
      find.byKey(ValueKey('attendance-status-${action.name}')),
    );

    expect(
      tilePosition(AttendanceAction.checkIn).dy,
      moreOrLessEquals(tilePosition(AttendanceAction.checkOut).dy),
    );
    expect(
      tilePosition(AttendanceAction.leave).dy,
      moreOrLessEquals(tilePosition(AttendanceAction.returnFromLeave).dy),
    );

    tester.view.physicalSize = const Size(320, 800);
    await tester.pumpAndSettle();

    final narrowPositions = AttendanceAction.values
        .map(tilePosition)
        .toList(growable: false);
    expect(
      narrowPositions.map((position) => position.dx).toSet(),
      hasLength(1),
    );
    for (var index = 1; index < narrowPositions.length; index++) {
      expect(
        narrowPositions[index - 1].dy,
        lessThan(narrowPositions[index].dy),
      );
    }
    expect(tester.takeException(), isNull);

    await links.close();
    schedules.dispose();
  });

  testWidgets('attendance status expires at the next Korean date', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();
    var now = DateTime.utc(2026, 7, 24, 14, 59, 59);

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: _WidgetTestAttendanceGateway(),
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();
    expect(find.text('오늘 출결 · 7월 24일(금)'), findsOneWidget);

    now = DateTime.utc(2026, 7, 24, 15, 0, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('오늘 출결 · 7월 24일(금)'), findsNothing);
    expect(find.text('오늘 출결 · 7월 25일(토)'), findsOneWidget);
    expect(find.text('확인 전'), findsNWidgets(4));
    expect(find.byTooltip('출결 상태 새로고침'), findsOneWidget);

    await links.close();
    schedules.dispose();
  });

  testWidgets(
    'confirmed attendance action highlights its tile and shows notice',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const profile = UserProfile(
        name: '윤동현',
        region: CampusRegion.pangyo5f,
        classNumber: 8,
      );
      final schedules = ScheduleController(ScheduleStore());
      await schedules.load();
      final links = StreamController<Uri>();
      final gateway = _WidgetTestAttendanceGateway(
        snapshot: const AttendanceSnapshot(
          networkAllowed: true,
          checkInTime: '2026-07-24T00:01:23.000Z',
        ),
        snapshotAfterAction: const AttendanceSnapshot(
          networkAllowed: true,
          checkInTime: '2026-07-24T00:01:23.000Z',
          earlyLeaveTime: '2026-07-24T03:34:56.000Z',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: AttendanceScreen(
              profile: profile,
              scheduleController: schedules,
              notificationScheduler: _NoOpNotificationScheduler(),
              onEditProfile: () async {},
              gateway: gateway,
              appLinkStream: links.stream,
              isAndroid: true,
              callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
              now: () => DateTime.utc(2026, 7, 24, 3),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(FilledButton, '외출'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '외출'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('외출 전송'));
      await tester.pumpAndSettle();

      expect(gateway.recordedAction, AttendanceAction.leave);
      expect(find.text('12:34'), findsOneWidget);
      final leaveTile = find.byKey(const ValueKey('attendance-status-leave'));
      expect(
        find.descendant(of: leaveTile, matching: find.text('방금 처리됨')),
        findsOneWidget,
      );
      expect(find.text('외출이 완료되었습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 5, milliseconds: 100));
      expect(find.text('방금 처리됨'), findsNothing);

      await links.close();
      schedules.dispose();
    },
  );

  testWidgets('revoked permissions reopen initial setup on app resume', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
      'initialSetup.completed': true,
    });
    final notifications = _SetupNotificationScheduler(granted: true);

    await tester.pumpWidget(
      SkalaAttendanceApp(
        notificationScheduler: notifications,
        callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('윤동현님, 안녕하세요'), findsOneWidget);

    notifications.granted = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('초기 설정'), findsOneWidget);
    expect(find.text('설정 필요'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('initialSetup.completed'), isFalse);
  });

  testWidgets('revoked permissions clear saved setup on next launch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
      'initialSetup.completed': true,
    });

    await tester.pumpWidget(
      SkalaAttendanceApp(
        notificationScheduler: _SetupNotificationScheduler(granted: false),
        callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('초기 설정'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('initialSetup.completed'), isFalse);
  });

  testWidgets('restored required permissions resync before returning home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
      'initialSetup.completed': true,
    });
    final notifications = _SetupNotificationScheduler(granted: true);

    await tester.pumpWidget(
      SkalaAttendanceApp(
        notificationScheduler: notifications,
        callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('윤동현님, 안녕하세요'), findsOneWidget);

    notifications.granted = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('초기 설정'), findsOneWidget);
    final syncCountBeforeRecovery = notifications.syncCount;

    await tester.tap(find.text('일정 알림'));
    await tester.pumpAndSettle();

    expect(find.text('윤동현님, 안녕하세요'), findsOneWidget);
    expect(notifications.syncCount, syncCountBeforeRecovery + 1);
  });

  testWidgets('revoked Android app links reopen initial setup on app resume', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
      'initialSetup.completed': true,
    });
    final links = _FakeCallbackLinkSettings(enabled: true);

    await tester.pumpWidget(
      SkalaAttendanceApp(
        notificationScheduler: _SetupNotificationScheduler(granted: true),
        callbackLinkSettings: links,
        isAndroid: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('윤동현님, 안녕하세요'), findsOneWidget);

    links.enabled = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('초기 설정'), findsOneWidget);
    expect(find.text('인증 후 앱 복귀'), findsOneWidget);
    expect(find.text('설정 필요'), findsOneWidget);
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

  testWidgets(
    'schedule editor keeps save accessible until inline save appears',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sticky-save-button')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('inline-save-button')),
        300,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('sticky-save-button')), findsNothing);
    },
  );

  testWidgets('schedule editor keeps inline save above system navigation', (
    tester,
  ) async {
    addTearDown(tester.view.resetPadding);
    tester.view.padding = const FakeViewPadding(bottom: 48);

    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('inline-save-button')),
      300,
    );
    await tester.pumpAndSettle();

    final buttonBottom = tester
        .getBottomRight(find.byKey(const Key('inline-save-button')))
        .dy;
    expect(
      buttonBottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 48),
    );
  });

  testWidgets('schedule editor briefly reveals its scrollbar on entry', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));
    await tester.pump();

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
      isTrue,
    );

    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
      isNull,
    );
  });

  testWidgets('schedule editor blocks an overlapping occurrence', (
    tester,
  ) async {
    const existing = AttendanceSchedule(
      id: 'existing',
      action: AttendanceAction.checkOut,
      hour: 9,
      minute: 0,
      weekdays: {DateTime.monday},
      enabled: false,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleEditScreen(existingSchedules: [existing]),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('inline-save-button')),
      300,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('inline-save-button')),
        matching: find.text('저장'),
      ),
    );
    await tester.pump();

    expect(find.textContaining('이미 퇴실 일정이 있습니다.'), findsOneWidget);
    expect(find.byType(ScheduleEditScreen), findsOneWidget);
  });

  testWidgets('weekly editor shows holidays matching selected weekdays', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));

    await tester.scrollUntilVisible(find.text('제외되는 공휴일 보기'), 200);
    await tester.pumpAndSettle();
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
    final scheduledAt = DateTime(2026, 7, 23, 9);
    final notifications = _NoOpNotificationScheduler()
      ..emit(
        '{"scheduleId":"check-in","action":"checkIn",'
        '"scheduledAt":"${scheduledAt.toIso8601String()}"}',
      );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    await schedules.saveSchedule(
      AttendanceSchedule(
        id: 'check-in',
        action: AttendanceAction.checkIn,
        hour: 9,
        minute: 0,
        weekdays: const {},
        enabled: true,
        recurrence: ScheduleRecurrence.once,
        date: DateTime(2026, 7, 23),
      ),
    );
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
    final scheduledAt = DateTime(2026, 7, 23, 12);
    final notifications = _NoOpNotificationScheduler()
      ..emit(
        '{"scheduleId":"leave","action":"leave",'
        '"scheduledAt":"${scheduledAt.toIso8601String()}"}',
      );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    await schedules.saveSchedule(
      AttendanceSchedule(
        id: 'leave',
        action: AttendanceAction.leave,
        hour: 12,
        minute: 0,
        weekdays: const {},
        enabled: true,
        recurrence: ScheduleRecurrence.once,
        date: DateTime(2026, 7, 23),
      ),
    );
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
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
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

  testWidgets('notification for a deleted schedule does not authenticate', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final notifications = _NoOpNotificationScheduler();
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
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifications.emit(
      '{"scheduleId":"deleted-check-in","action":"checkIn",'
      '"scheduledAt":"2026-07-23T09:00:00.000"}',
    );
    await tester.pumpAndSettle();

    expect(gateway.authenticationCallCount, 0);
    expect(notifications.tapPayload.value, isNull);
    expect(find.textContaining('변경되거나 삭제된 일정의 알림'), findsOneWidget);
    schedules.dispose();
  });

  testWidgets('notification with an old time does not authenticate', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    await schedules.saveSchedule(
      AttendanceSchedule(
        id: 'changed-check-out',
        action: AttendanceAction.checkOut,
        hour: 18,
        minute: 30,
        weekdays: const {},
        enabled: true,
        recurrence: ScheduleRecurrence.once,
        date: DateTime(2026, 7, 23),
      ),
    );
    final notifications = _NoOpNotificationScheduler();
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
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifications.emit(
      '{"scheduleId":"changed-check-out","action":"checkOut",'
      '"scheduledAt":"2026-07-23T18:00:00.000"}',
    );
    await tester.pumpAndSettle();

    expect(gateway.authenticationCallCount, 0);
    expect(notifications.tapPayload.value, isNull);
    expect(find.textContaining('변경되거나 삭제된 일정의 알림'), findsOneWidget);
    schedules.dispose();
  });

  testWidgets('notification tapped while busy is handled after busy clears', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    await schedules.saveSchedule(
      AttendanceSchedule(
        id: 'queued-check-in',
        action: AttendanceAction.checkIn,
        hour: 9,
        minute: 0,
        weekdays: const {},
        enabled: true,
        recurrence: ScheduleRecurrence.once,
        date: DateTime(2026, 7, 23),
      ),
    );
    final notifications = _NoOpNotificationScheduler();
    final links = StreamController<Uri>();
    final fetchGate = Completer<void>();
    final gateway = _WidgetTestAttendanceGateway(fetchGate: fetchGate);

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: notifications,
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pump();
    notifications.emit(
      '{"scheduleId":"queued-check-in","action":"checkIn",'
      '"scheduledAt":"2026-07-23T09:00:00.000"}',
    );
    await tester.pump();

    expect(notifications.tapPayload.value, isNotNull);
    fetchGate.complete();
    await tester.pumpAndSettle();

    expect(notifications.tapPayload.value, isNull);
    expect(gateway.authenticationCallCount, 0);
    expect(gateway.fetchCallCount, 3);
    expect(gateway.recordedAction, AttendanceAction.checkIn);
    await links.close();
    schedules.dispose();
  });

  testWidgets('notification waits for saved schedules to finish loading', (
    tester,
  ) async {
    final stored = AttendanceSchedule(
      id: 'loading-check-in',
      action: AttendanceAction.checkIn,
      hour: 9,
      minute: 0,
      weekdays: const {},
      enabled: true,
      recurrence: ScheduleRecurrence.once,
      date: DateTime(2026, 7, 23),
    );
    SharedPreferences.setMockInitialValues({
      'attendance.schedules': jsonEncode([stored.toJson()]),
    });
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    final notifications = _NoOpNotificationScheduler()
      ..emit(
        '{"scheduleId":"loading-check-in","action":"checkIn",'
        '"scheduledAt":"2026-07-23T09:00:00.000"}',
      );
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
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(gateway.authenticationCallCount, 0);
    expect(notifications.tapPayload.value, isNotNull);

    await schedules.load();
    await tester.pumpAndSettle();

    expect(gateway.authenticationCallCount, 1);
    expect(notifications.tapPayload.value, isNull);
    schedules.dispose();
  });

  testWidgets('Android authentication guides users to app link settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final gateway = _WidgetTestAttendanceGateway();
    final linkSettings = _FakeCallbackLinkSettings(
      enabled: false,
      enableOnOpen: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: const Stream.empty(),
          isAndroid: true,
          callbackLinkSettings: linkSettings,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('출결 상태 새로고침'));
    await tester.pumpAndSettle();

    expect(find.text('앱 복귀 설정이 필요합니다'), findsOneWidget);
    expect(gateway.authenticationProfile, isNull);

    await tester.tap(find.text('링크 설정 열기'));
    await tester.pumpAndSettle();
    expect(linkSettings.openCount, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.authenticationProfile, profile);
    schedules.dispose();
  });

  testWidgets('canceling app link settings abandons the pending action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();
    final gateway = _WidgetTestAttendanceGateway(
      snapshot: const AttendanceSnapshot(
        networkAllowed: true,
        checkInTime: '09:00',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: false),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(FilledButton, '외출'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '외출'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();

    expect(find.text('외출 처리'), findsNothing);
    expect(gateway.recordedAction, isNull);
    expect(find.text('09:00'), findsOneWidget);

    await links.close();
    schedules.dispose();
  });

  testWidgets('iOS keeps attendance handling in the manual browser flow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = ScheduleController(ScheduleStore());
    await schedules.load();
    final links = StreamController<Uri>();
    final gateway = _WidgetTestAttendanceGateway();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _NoOpNotificationScheduler(),
          onEditProfile: () async {},
          gateway: gateway,
          appLinkStream: links.stream,
          isAndroid: false,
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '입실'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '입실'));
    await tester.pumpAndSettle();

    expect(gateway.authenticationCallCount, 1);
    expect(find.textContaining('Safari'), findsOneWidget);

    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();

    expect(gateway.fetchCallCount, 0);
    expect(gateway.recordedAction, isNull);
    expect(find.text('확인 전'), findsNWidgets(4));

    await links.close();
    schedules.dispose();
  });

  testWidgets('initial setup requests notification permissions', (
    tester,
  ) async {
    final notifications = _SetupNotificationScheduler(granted: false);
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: InitialSetupScreen(
          notificationScheduler: notifications,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          isAndroid: false,
          onFinished: () async => finished = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('초기 설정'), findsOneWidget);
    expect(find.text('설정 필요'), findsOneWidget);
    expect(find.text('설정하기'), findsNothing);
    expect(find.text('나중에 설정'), findsNothing);
    expect(find.textContaining('나중에 설정해도'), findsNothing);
    await tester.tap(find.text('일정 알림'));
    await tester.pumpAndSettle();

    expect(notifications.requestCount, 1);
    expect(finished, isTrue);
  });

  testWidgets(
    'required setup waits for notification resync and retries failure',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'profile.name': '윤동현',
        'profile.region': 'P2',
        'profile.classNumber': 8,
      });
      final notifications = _SetupNotificationScheduler(
        granted: true,
        failSync: true,
      );

      await tester.pumpWidget(
        SkalaAttendanceApp(
          notificationScheduler: notifications,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('초기 설정'), findsOneWidget);
      expect(find.textContaining('알림을 예약하지 못했습니다'), findsOneWidget);
      expect(find.text('윤동현님, 안녕하세요'), findsNothing);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('initialSetup.completed'), isNot(true));

      notifications.failSync = false;
      await tester.tap(find.text('설정 완료'));
      await tester.pumpAndSettle();

      expect(find.text('윤동현님, 안녕하세요'), findsOneWidget);
      expect(preferences.getBool('initialSetup.completed'), isTrue);
    },
  );

  testWidgets('denied iOS notifications open Settings and resume setup', (
    tester,
  ) async {
    final notifications = _SetupNotificationScheduler(
      granted: false,
      grantOnRequest: false,
    );
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: InitialSetupScreen(
          notificationScheduler: notifications,
          callbackLinkSettings: _FakeCallbackLinkSettings(enabled: true),
          isAndroid: false,
          onFinished: () async => finished = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('일정 알림'));
    await tester.pumpAndSettle();

    expect(find.text('알림 권한 설정'), findsOneWidget);
    expect(find.textContaining('설정 → 앱 → SKALA 출결 도우미 → 알림'), findsOneWidget);
    expect(notifications.openSettingsCount, 0);

    await tester.tap(find.text('설정 화면 열기'));
    await tester.pumpAndSettle();
    expect(notifications.openSettingsCount, 1);
    expect(finished, isFalse);

    notifications.granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('initial setup resumes after Android app link approval', (
    tester,
  ) async {
    final links = _FakeCallbackLinkSettings(enabled: false, enableOnOpen: true);
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: InitialSetupScreen(
          notificationScheduler: _SetupNotificationScheduler(granted: true),
          callbackLinkSettings: links,
          isAndroid: true,
          onFinished: () async => finished = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('설정 방법'), findsNothing);
    await tester.tap(find.text('인증 후 앱 복귀'));
    await tester.pumpAndSettle();

    expect(find.text('인증 후 앱 복귀 설정'), findsOneWidget);
    expect(find.text('지원되는 링크 열기'), findsOneWidget);
    expect(find.text('지원되는 웹 주소'), findsOneWidget);
    expect(find.text('att.skala-ai.com'), findsOneWidget);
    expect(links.openCount, 0);

    await tester.tap(find.text('설정 화면 열기'));
    await tester.pumpAndSettle();
    expect(links.openCount, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets(
    'combined Android setup waits for notifications before link guide',
    (tester) async {
      final notifications = _SetupNotificationScheduler(
        granted: false,
        grantOnRequest: false,
      );
      final links = _FakeCallbackLinkSettings(enabled: false);

      await tester.pumpWidget(
        MaterialApp(
          home: InitialSetupScreen(
            notificationScheduler: notifications,
            callbackLinkSettings: links,
            isAndroid: true,
            onFinished: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('필요한 설정 계속하기'));
      await tester.pumpAndSettle();
      expect(find.text('인증 후 앱 복귀 설정'), findsNothing);
      expect(links.openCount, 0);

      notifications.granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('인증 후 앱 복귀 설정'), findsOneWidget);
      expect(links.openCount, 0);

      await tester.tap(find.text('설정 화면 열기'));
      await tester.pumpAndSettle();
      expect(links.openCount, 1);
    },
  );
}

class _SetupNotificationScheduler extends _NoOpNotificationScheduler {
  _SetupNotificationScheduler({
    required this.granted,
    this.grantOnRequest = true,
    this.failSync = false,
  });

  bool granted;
  final bool grantOnRequest;
  bool failSync;
  int requestCount = 0;
  int openSettingsCount = 0;
  int syncCount = 0;

  @override
  Future<bool> arePermissionsGranted() async => granted;

  @override
  Future<bool> requestPermissions() async {
    requestCount++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<void> openPermissionSettings() async => openSettingsCount++;

  @override
  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now}) async {
    syncCount++;
    if (failSync) throw StateError('sync failed');
    return schedules.length;
  }
}

class _FakeCallbackLinkSettings implements CallbackLinkSettings {
  _FakeCallbackLinkSettings({required this.enabled, this.enableOnOpen = false});

  bool enabled;
  final bool enableOnOpen;
  int openCount = 0;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> open() async {
    openCount++;
    if (enableOnOpen) enabled = true;
  }
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
  Future<void> openPermissionSettings() async {}

  @override
  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now}) async =>
      0;
}

class _DelayedInitializationNotificationScheduler
    extends _NoOpNotificationScheduler {
  bool initializationStarted = false;
  final _gate = Completer<void>();

  @override
  Future<void> initialize() {
    initializationStarted = true;
    return _gate.future;
  }
}

class _WidgetTestAttendanceGateway implements AttendanceGateway {
  _WidgetTestAttendanceGateway({
    this.snapshot = const AttendanceSnapshot(networkAllowed: true),
    this.snapshotAfterAction,
    this.fetchGate,
  });

  AttendanceSnapshot snapshot;
  final AttendanceSnapshot? snapshotAfterAction;
  final Completer<void>? fetchGate;
  UserProfile? authenticationProfile;
  AttendanceAction? recordedAction;
  int authenticationCallCount = 0;
  int fetchCallCount = 0;

  @override
  Future<void> startBrowserAuthentication(UserProfile profile) async {
    authenticationCallCount++;
    authenticationProfile = profile;
  }

  @override
  Future<AttendanceSnapshot> fetchToday(String token) async {
    fetchCallCount++;
    await fetchGate?.future;
    return snapshot;
  }

  @override
  Future<void> recordAction(String token, AttendanceAction action) async {
    recordedAction = action;
    snapshot = snapshotAfterAction ?? snapshot;
  }

  @override
  void validateAttendanceToken(String token, UserProfile profile) {}

  @override
  void close() {}
}

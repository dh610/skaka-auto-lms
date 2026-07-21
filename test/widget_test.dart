import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/app/app.dart';
import 'package:skala_attendance/app/initial_setup_screen.dart';
import 'package:skala_attendance/features/attendance/data/attendance_gateway.dart';
import 'package:skala_attendance/features/attendance/data/callback_link_settings.dart';
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
    await tester.tap(find.text('일정 관리'));
    await tester.pumpAndSettle();

    expect(find.text('출결 일정 관리'), findsOneWidget);
    expect(find.text('알림 권한 설정'), findsNothing);
    schedules.dispose();
  });

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

    await tester.scrollUntilVisible(find.text('저장'), 300);
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pump();

    expect(find.textContaining('이미 퇴실 일정이 있습니다.'), findsOneWidget);
    expect(find.byType(ScheduleEditScreen), findsOneWidget);
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
    final scheduledAt = DateTime.now().subtract(const Duration(minutes: 1));
    final notifications = _NoOpNotificationScheduler()
      ..emit(
        '{"scheduleId":"check-in","action":"checkIn",'
        '"scheduledAt":"${scheduledAt.toIso8601String()}"}',
      );
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
    final scheduledAt = DateTime.now().subtract(const Duration(minutes: 1));
    final notifications = _NoOpNotificationScheduler()
      ..emit(
        '{"scheduleId":"leave","action":"leave",'
        '"scheduledAt":"${scheduledAt.toIso8601String()}"}',
      );
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
    await tester.tap(find.text('Google 인증 시작'));
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
    await tester.tap(find.text('일정 알림'));
    await tester.pumpAndSettle();

    expect(notifications.requestCount, 1);
    expect(finished, isTrue);
  });

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
}

class _SetupNotificationScheduler extends _NoOpNotificationScheduler {
  _SetupNotificationScheduler({
    required this.granted,
    this.grantOnRequest = true,
  });

  bool granted;
  final bool grantOnRequest;
  int requestCount = 0;
  int openSettingsCount = 0;

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

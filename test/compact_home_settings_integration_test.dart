import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/app/app.dart';
import 'package:skala_attendance/app/theme_mode_store.dart';
import 'package:skala_attendance/features/attendance/data/attendance_gateway.dart';
import 'package:skala_attendance/features/attendance/data/callback_link_settings.dart';
import 'package:skala_attendance/features/attendance/domain/attendance_snapshot.dart';
import 'package:skala_attendance/features/attendance/presentation/attendance_screen.dart';
import 'package:skala_attendance/features/profile/domain/profile_verifier.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';
import 'package:skala_attendance/features/schedule/application/notification_scheduler.dart';
import 'package:skala_attendance/features/schedule/application/schedule_controller.dart';
import 'package:skala_attendance/features/schedule/data/schedule_store.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';
import 'package:skala_attendance/features/settings/domain/app_version.dart';

void main() {
  const profile = UserProfile(
    name: '윤동현',
    region: CampusRegion.pangyo5f,
    classNumber: 8,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home exposes Settings and removes profile and theme chrome', (
    tester,
  ) async {
    final schedules = await _schedules();
    var settingsOpenCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _Scheduler(),
          onEditProfile: () async {},
          onOpenSettings: () => settingsOpenCount += 1,
          gateway: _Gateway(),
          appLinkStream: const Stream.empty(),
          isAndroid: true,
          callbackLinkSettings: _CallbackSettings(),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('설정'), findsOneWidget);
    expect(find.byTooltip('테마 설정'), findsNothing);
    expect(find.text('윤동현님, 안녕하세요'), findsNothing);
    expect(find.text('오늘의 출결 일정과 상태를 확인하세요.'), findsNothing);
    expect(find.text('사용자 정보 변경'), findsNothing);
    expect(
      find.text('우측 상단 새로고침 버튼을 눌러 Google 인증 후 출결 정보를 갱신하세요.'),
      findsOneWidget,
    );
    expect(find.text('Google 인증 다시 시도'), findsNothing);

    await tester.tap(find.byTooltip('설정'));
    expect(settingsOpenCount, 1);
    schedules.dispose();
  });

  testWidgets('compact phone home initially reveals Today schedule title', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final schedules = await _schedules();
    await schedules.saveSchedule(
      const AttendanceSchedule(
        id: 'today-alarm',
        action: AttendanceAction.checkIn,
        hour: 8,
        minute: 50,
        weekdays: {1, 2, 3, 4, 5},
        enabled: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _Scheduler(),
          onEditProfile: () async {},
          onOpenSettings: () {},
          gateway: _Gateway(),
          appLinkStream: const Stream.empty(),
          isAndroid: true,
          callbackLinkSettings: _CallbackSettings(),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scheduleTitle = find.text('오늘의 알람');
    expect(scheduleTitle, findsOneWidget);
    expect(find.text('오전 8:50 · 입실'), findsOneWidget);
    expect(find.text('예정'), findsNothing);
    expect(find.text('시간 지남'), findsNothing);
    expect(find.text('건너뜀'), findsNothing);
    expect(tester.getTopLeft(scheduleTitle).dy, lessThan(844));
    expect(
      tester.getTopLeft(find.text('오늘 출결 · 7월 24일(금)')).dy,
      lessThan(tester.getTopLeft(scheduleTitle).dy),
    );
    final tiles = AttendanceAction.values
        .map(
          (action) => tester.getRect(
            find.byKey(ValueKey('attendance-status-${action.name}')),
          ),
        )
        .toList();
    expect(tiles[0].top, moreOrLessEquals(tiles[1].top));
    expect(tiles[2].top, moreOrLessEquals(tiles[3].top));
    expect(tiles.every((tile) => tile.height <= 72), isTrue);
    schedules.dispose();
  });

  testWidgets('queried success hides generic box but keeps recent feedback', (
    tester,
  ) async {
    final schedules = await _schedules();
    final links = StreamController<Uri>();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _Scheduler(),
          onEditProfile: () async {},
          onOpenSettings: () {},
          gateway: _Gateway(),
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _CallbackSettings(),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('출결 상태 새로고침'));
    await tester.pump();
    await tester.pump();
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();

    expect(find.text('방금 업데이트됨'), findsOneWidget);
    expect(find.text('인증 및 상태 조회에 성공했습니다.'), findsNothing);
    await links.close();
    schedules.dispose();
  });

  testWidgets('browser cancellation uses refresh-only recovery message', (
    tester,
  ) async {
    final schedules = await _schedules();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _Scheduler(),
          onEditProfile: () async {},
          onOpenSettings: () {},
          gateway: _Gateway(),
          appLinkStream: const Stream.empty(),
          isAndroid: true,
          callbackLinkSettings: _CallbackSettings(),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('출결 상태 새로고침'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(
      find.text('Google 인증이 완료되지 않았습니다. 새로고침 버튼을 눌러 다시 시도해 주세요.'),
      findsOneWidget,
    );
    expect(find.text('Google 인증 다시 시도'), findsNothing);
    schedules.dispose();
  });

  testWidgets('status errors direct recovery through the header refresh', (
    tester,
  ) async {
    final schedules = await _schedules();
    final links = StreamController<Uri>();

    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          profile: profile,
          scheduleController: schedules,
          notificationScheduler: _Scheduler(),
          onOpenSettings: () {},
          gateway: _Gateway(fetchError: StateError('offline')),
          appLinkStream: links.stream,
          isAndroid: true,
          callbackLinkSettings: _CallbackSettings(),
          now: () => DateTime.utc(2026, 7, 24, 3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('출결 상태 새로고침'));
    await tester.pump();
    await tester.pump();
    links.add(Uri.parse('https://att.skala-ai.com?token=test-token'));
    await tester.pumpAndSettle();

    expect(find.textContaining('새로고침 버튼을 눌러 다시 확인해 주세요.'), findsOneWidget);
    expect(find.text('Google 인증 다시 시도'), findsNothing);
    await links.close();
    schedules.dispose();
  });

  testWidgets('app composes Settings with injected platform data', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
      'initialSetup.completed': true,
    });
    final scheduler = _Scheduler();

    await tester.pumpWidget(
      SkalaAttendanceApp(
        notificationScheduler: scheduler,
        notificationPermissionSettings: scheduler,
        callbackLinkSettings: _CallbackSettings(),
        appVersionProvider: _VersionProvider(),
        profileVerifier: _Verifier(),
        isAndroid: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('윤동현'), findsOneWidget);
    expect(find.text('알림 권한'), findsOneWidget);
    expect(find.text('정확한 알람 권한'), findsOneWidget);
    expect(find.text('인증 후 앱 복귀 설정'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('버전 7.8.9 (빌드 321)'), 200);
    expect(find.text('버전 7.8.9 (빌드 321)'), findsOneWidget);
  });

  testWidgets('profile edit updates Settings and remains after returning', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
      'initialSetup.completed': true,
    });
    final scheduler = _Scheduler();
    final gateways = <_Gateway>[];

    await tester.pumpWidget(
      SkalaAttendanceApp(
        notificationScheduler: scheduler,
        notificationPermissionSettings: scheduler,
        callbackLinkSettings: _CallbackSettings(),
        appVersionProvider: _VersionProvider(),
        profileVerifier: _Verifier(),
        attendanceGatewayFactory: () {
          final gateway = _Gateway();
          gateways.add(gateway);
          return gateway;
        },
        isAndroid: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사용자 정보 변경'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '김스칼라');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('김스칼라'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('설정'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '입실'));
    await tester.pump();
    await tester.pump();
    expect(gateways, hasLength(1));
    expect(gateways.single.authenticationProfile?.name, '김스칼라');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    expect(find.text('김스칼라'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(gateways.single.closeCount, 1);
  });

  testWidgets('attendance gateway factory creates once per screen state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const profile = UserProfile(
      name: '윤동현',
      region: CampusRegion.pangyo5f,
      classNumber: 8,
    );
    final schedules = await _schedules();
    final scheduler = _Scheduler();
    final gateways = <_Gateway>[];

    Widget screen(Key key) => MaterialApp(
      home: AttendanceScreen(
        key: key,
        profile: profile,
        scheduleController: schedules,
        notificationScheduler: scheduler,
        gatewayFactory: () {
          final gateway = _Gateway();
          gateways.add(gateway);
          return gateway;
        },
        appLinkStream: const Stream.empty(),
        isAndroid: true,
        callbackLinkSettings: _CallbackSettings(),
      ),
    );

    await tester.pumpWidget(screen(const ValueKey('first')));
    await tester.pump();
    expect(gateways, hasLength(1));

    await tester.pumpWidget(screen(const ValueKey('first')));
    await tester.pump();
    expect(gateways, hasLength(1));
    expect(gateways.first.closeCount, 0);

    await tester.pumpWidget(screen(const ValueKey('second')));
    await tester.pump();
    expect(gateways, hasLength(2));
    expect(gateways.first.closeCount, 1);
    expect(gateways.last.closeCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(gateways.first.closeCount, 1);
    expect(gateways.last.closeCount, 1);
    schedules.dispose();
  });

  testWidgets(
    'app shows the second rapid theme before ordered persistence completes',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'profile.name': '윤동현',
        'profile.region': 'P2',
        'profile.classNumber': 8,
        'initialSetup.completed': true,
      });
      final scheduler = _Scheduler();
      final themeStore = _GatedThemeModeStore();

      await tester.pumpWidget(
        SkalaAttendanceApp(
          notificationScheduler: scheduler,
          notificationPermissionSettings: scheduler,
          callbackLinkSettings: _CallbackSettings(),
          appVersionProvider: _VersionProvider(),
          profileVerifier: _Verifier(),
          themeModeStore: themeStore,
          isAndroid: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();

      Finder themeTile() =>
          find.ancestor(of: find.text('테마'), matching: find.byType(ListTile));

      await tester.tap(themeTile());
      await tester.pumpAndSettle();
      await tester.tap(find.text('다크').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(themeStore.saveCalls, [ThemeMode.dark]);

      await tester.tap(themeTile());
      await tester.pumpAndSettle();
      await tester.tap(find.text('라이트').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(themeStore.saveCalls, [ThemeMode.dark]);

      themeStore.darkSave.complete();
      await tester.pump();
      await tester.pump();
      expect(themeStore.saveCalls, [ThemeMode.dark, ThemeMode.light]);

      themeStore.lightSave.complete();
      await tester.pumpAndSettle();
    },
  );
}

Future<ScheduleController> _schedules() async {
  final controller = ScheduleController(ScheduleStore(), _Scheduler());
  await controller.load();
  return controller;
}

class _Scheduler
    implements NotificationScheduler, NotificationPermissionSettings {
  final _payload = ValueNotifier<String?>(null);

  @override
  ValueListenable<String?> get tapPayload => _payload;

  @override
  Future<bool> arePermissionsGranted() async => true;

  @override
  void consumeTap() => _payload.value = null;

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async =>
      const NotificationPermissionStatus.android(
        notificationsAllowed: true,
        exactAlarmsAllowed: true,
      );

  @override
  Future<void> initialize() async {}

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> openPermissionSettings() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now}) async =>
      schedules.length;
}

class _CallbackSettings implements CallbackLinkSettings {
  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<void> open() async {}
}

class _Gateway implements AttendanceGateway {
  _Gateway({this.fetchError});

  final Object? fetchError;
  UserProfile? authenticationProfile;
  int closeCount = 0;

  @override
  void close() {
    closeCount++;
  }

  @override
  Future<AttendanceSnapshot> fetchToday(String token) async {
    if (fetchError case final error?) throw error;
    return const AttendanceSnapshot(networkAllowed: true);
  }

  @override
  Future<void> recordAction(String token, AttendanceAction action) async {}

  @override
  Future<void> startBrowserAuthentication(UserProfile profile) async {
    authenticationProfile = profile;
  }

  @override
  void validateAttendanceToken(String token, UserProfile profile) {}
}

class _VersionProvider implements AppVersionProvider {
  @override
  Future<AppVersion> getAppVersion() async =>
      const AppVersion(version: '7.8.9', buildNumber: '321');
}

class _Verifier implements ProfileVerifier {
  @override
  void close() {}

  @override
  Future<void> verify(UserProfile profile) async {}
}

class _GatedThemeModeStore extends ThemeModeStore {
  final darkSave = Completer<void>();
  final lightSave = Completer<void>();
  final saveCalls = <ThemeMode>[];

  @override
  Future<ThemeMode> load() async => ThemeMode.system;

  @override
  Future<void> save(ThemeMode mode) {
    saveCalls.add(mode);
    return switch (mode) {
      ThemeMode.dark => darkSave.future,
      ThemeMode.light => lightSave.future,
      ThemeMode.system => Future<void>.value(),
    };
  }
}

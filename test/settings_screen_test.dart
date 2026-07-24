import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skala_attendance/features/attendance/data/callback_link_settings.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';
import 'package:skala_attendance/features/schedule/application/notification_scheduler.dart';
import 'package:skala_attendance/features/settings/domain/app_version.dart';
import 'package:skala_attendance/features/settings/presentation/settings_screen.dart';

void main() {
  const profile = UserProfile(
    name: '윤동현',
    region: CampusRegion.pangyo5f,
    classNumber: 8,
  );

  testWidgets('Android shows every settings section and injected value', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        profile: profile,
        themeMode: ThemeMode.dark,
        isAndroid: true,
        notifications: _NotificationSettings(
          const NotificationPermissionStatus(
            notificationsAllowed: true,
            exactAlarmsAllowed: false,
          ),
        ),
        callbacks: _CallbackSettings(enabled: true),
        versions: _VersionProvider(
          const AppVersion(version: '9.8.7', buildNumber: '6543'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('설정'), findsOneWidget);
    expect(find.text('사용자 정보'), findsOneWidget);
    expect(find.text('화면 설정'), findsOneWidget);
    expect(find.text('권한 및 필수 설정'), findsOneWidget);
    expect(find.text('윤동현'), findsOneWidget);
    expect(find.text('판교캠퍼스 5F · 8반'), findsOneWidget);
    expect(find.text('다크'), findsOneWidget);
    expect(find.text('알림 권한'), findsOneWidget);
    expect(find.text('정확한 알람 권한'), findsOneWidget);
    expect(find.text('인증 후 앱 복귀 설정'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('앱 정보'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('앱 정보'), findsOneWidget);
    expect(find.text('버전 9.8.7 (빌드 6543)'), findsOneWidget);
  });

  testWidgets(
    'iOS shows only notification permission and skips App Link read',
    (tester) async {
      final callbacks = _CallbackSettings(enabled: true);

      await tester.pumpWidget(
        _app(
          profile: profile,
          themeMode: ThemeMode.system,
          isAndroid: false,
          notifications: _NotificationSettings(
            const NotificationPermissionStatus(
              notificationsAllowed: true,
              exactAlarmsAllowed: null,
            ),
          ),
          callbacks: callbacks,
          versions: _VersionProvider(
            const AppVersion(version: '1.2.3', buildNumber: '45'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('알림 권한'), findsOneWidget);
      expect(find.text('정확한 알람 권한'), findsNothing);
      expect(find.text('인증 후 앱 복귀 설정'), findsNothing);
      expect(callbacks.statusReadCount, 0);
    },
  );

  testWidgets(
    'permission states use text and icons and failures stay isolated',
    (tester) async {
      await tester.pumpWidget(
        _app(
          profile: profile,
          themeMode: ThemeMode.light,
          isAndroid: true,
          notifications: _NotificationSettings(
            const NotificationPermissionStatus(
              notificationsAllowed: true,
              exactAlarmsAllowed: false,
            ),
          ),
          callbacks: _CallbackSettings(
            enabled: false,
            statusError: StateError('unavailable'),
          ),
          versions: _VersionProvider(
            null,
            error: StateError('version unavailable'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('허용됨'), findsOneWidget);
      expect(find.text('설정 필요'), findsOneWidget);
      expect(find.text('확인할 수 없음'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('버전 정보를 확인할 수 없음'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('버전 정보를 확인할 수 없음'), findsOneWidget);
    },
  );

  testWidgets('permission rows call only their matching settings operation', (
    tester,
  ) async {
    final notifications = _NotificationSettings(
      const NotificationPermissionStatus(
        notificationsAllowed: false,
        exactAlarmsAllowed: false,
      ),
    );
    final callbacks = _CallbackSettings(enabled: false);
    await tester.pumpWidget(
      _app(
        profile: profile,
        themeMode: ThemeMode.system,
        isAndroid: true,
        notifications: notifications,
        callbacks: callbacks,
        versions: _VersionProvider(
          const AppVersion(version: '1.2.3', buildNumber: '45'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('알림 권한'));
    await tester.pump();
    expect(notifications.notificationOpenCount, 1);
    expect(notifications.exactAlarmOpenCount, 0);
    expect(callbacks.openCount, 0);

    await tester.tap(find.text('정확한 알람 권한'));
    await tester.pump();
    expect(notifications.notificationOpenCount, 1);
    expect(notifications.exactAlarmOpenCount, 1);
    expect(callbacks.openCount, 0);

    await tester.ensureVisible(find.text('인증 후 앱 복귀 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('인증 후 앱 복귀 설정'));
    await tester.pump();
    expect(notifications.notificationOpenCount, 1);
    expect(notifications.exactAlarmOpenCount, 1);
    expect(callbacks.openCount, 1);
  });

  testWidgets('settings-opening failure shows a snackbar', (tester) async {
    final notifications = _NotificationSettings(
      const NotificationPermissionStatus(
        notificationsAllowed: false,
        exactAlarmsAllowed: null,
      ),
      notificationOpenError: StateError('cannot open'),
    );
    await tester.pumpWidget(
      _app(
        profile: profile,
        themeMode: ThemeMode.system,
        isAndroid: false,
        notifications: notifications,
        callbacks: _CallbackSettings(enabled: true),
        versions: _VersionProvider(
          const AppVersion(version: '1.2.3', buildNumber: '45'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('알림 권한'));
    await tester.pump();

    expect(find.text('알림 설정 화면을 열지 못했습니다.'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
  });

  testWidgets('resume reloads permission and callback statuses', (
    tester,
  ) async {
    final notifications = _NotificationSettings(
      const NotificationPermissionStatus(
        notificationsAllowed: false,
        exactAlarmsAllowed: false,
      ),
    );
    final callbacks = _CallbackSettings(enabled: false);
    await tester.pumpWidget(
      _app(
        profile: profile,
        themeMode: ThemeMode.system,
        isAndroid: true,
        notifications: notifications,
        callbacks: callbacks,
        versions: _VersionProvider(
          const AppVersion(version: '1.2.3', buildNumber: '45'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(notifications.statusReadCount, 1);
    expect(callbacks.statusReadCount, 1);

    notifications.status = const NotificationPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: true,
    );
    callbacks.enabled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(notifications.statusReadCount, 2);
    expect(callbacks.statusReadCount, 2);
    expect(find.text('허용됨'), findsNWidgets(3));
  });

  testWidgets(
    'profile and theme choices update immediately and invoke callbacks',
    (tester) async {
      const changedProfile = UserProfile(
        name: '김스칼라',
        region: CampusRegion.pangyo4f,
        classNumber: 3,
      );
      var profileEditCount = 0;
      final persistedThemes = <ThemeMode>[];
      await tester.pumpWidget(
        _app(
          profile: profile,
          themeMode: ThemeMode.system,
          isAndroid: false,
          notifications: _NotificationSettings(
            const NotificationPermissionStatus(
              notificationsAllowed: true,
              exactAlarmsAllowed: null,
            ),
          ),
          callbacks: _CallbackSettings(enabled: true),
          versions: _VersionProvider(
            const AppVersion(version: '1.2.3', buildNumber: '45'),
          ),
          editProfile: () async {
            profileEditCount += 1;
            return changedProfile;
          },
          persistThemeMode: (mode) async => persistedThemes.add(mode),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('사용자 정보 변경'));
      await tester.pump();
      expect(profileEditCount, 1);
      expect(find.text('김스칼라'), findsOneWidget);
      expect(find.text('판교캠퍼스 4F · 3반'), findsOneWidget);

      await tester.tap(find.text('시스템 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('다크').last);
      await tester.pumpAndSettle();

      expect(persistedThemes, [ThemeMode.dark]);
      expect(find.text('다크'), findsOneWidget);
    },
  );

  testWidgets('large text stays scrollable without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3)),
        child: _app(
          profile: profile,
          themeMode: ThemeMode.system,
          isAndroid: true,
          notifications: _NotificationSettings(
            const NotificationPermissionStatus(
              notificationsAllowed: true,
              exactAlarmsAllowed: true,
            ),
          ),
          callbacks: _CallbackSettings(enabled: true),
          versions: _VersionProvider(
            const AppVersion(version: '1.2.3', buildNumber: '45'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('버전 1.2.3 (빌드 45)'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('버전 1.2.3 (빌드 45)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  required UserProfile profile,
  required ThemeMode themeMode,
  required bool isAndroid,
  required _NotificationSettings notifications,
  required _CallbackSettings callbacks,
  required _VersionProvider versions,
  Future<UserProfile?> Function()? editProfile,
  Future<void> Function(ThemeMode)? persistThemeMode,
}) {
  return MaterialApp(
    home: SettingsScreen(
      profile: profile,
      themeMode: themeMode,
      isAndroid: isAndroid,
      notificationSettings: notifications,
      callbackLinkSettings: callbacks,
      appVersionProvider: versions,
      onEditProfile: editProfile ?? () async => null,
      onThemeModeChanged: persistThemeMode ?? (_) async {},
    ),
  );
}

class _NotificationSettings implements NotificationPermissionSettings {
  _NotificationSettings(this.status, {this.notificationOpenError});

  NotificationPermissionStatus status;
  final Object? notificationOpenError;
  int statusReadCount = 0;
  int notificationOpenCount = 0;
  int exactAlarmOpenCount = 0;

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    statusReadCount += 1;
    return status;
  }

  @override
  Future<void> openExactAlarmSettings() async {
    exactAlarmOpenCount += 1;
  }

  @override
  Future<void> openNotificationSettings() async {
    notificationOpenCount += 1;
    if (notificationOpenError case final error?) throw error;
  }
}

class _CallbackSettings implements CallbackLinkSettings {
  _CallbackSettings({required this.enabled, this.statusError});

  bool enabled;
  final Object? statusError;
  int statusReadCount = 0;
  int openCount = 0;

  @override
  Future<bool> isEnabled() async {
    statusReadCount += 1;
    if (statusError case final error?) throw error;
    return enabled;
  }

  @override
  Future<void> open() async {
    openCount += 1;
  }
}

class _VersionProvider implements AppVersionProvider {
  _VersionProvider(this.version, {this.error});

  final AppVersion? version;
  final Object? error;

  @override
  Future<AppVersion> getAppVersion() async {
    if (error case final failure?) throw failure;
    return version!;
  }
}

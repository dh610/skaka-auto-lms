import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skala_attendance/features/attendance/data/callback_link_settings.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';
import 'package:skala_attendance/features/schedule/application/notification_scheduler.dart';
import 'package:skala_attendance/features/settings/application/settings_controller.dart';
import 'package:skala_attendance/features/settings/domain/app_version.dart';

void main() {
  const profile = UserProfile(
    name: '윤동현',
    region: CampusRegion.pangyo5f,
    classNumber: 8,
  );

  test('refresh failures remain isolated by settings group', () async {
    final controller = SettingsController(
      initialProfile: profile,
      initialThemeMode: ThemeMode.dark,
      isAndroid: true,
      notificationSettings: _NotificationSettings(
        statusError: StateError('notifications unavailable'),
      ),
      callbackLinkSettings: _CallbackSettings(enabled: true),
      appVersionProvider: _VersionProvider(
        const AppVersion(version: '9.8.7', buildNumber: '6543'),
      ),
      editProfile: () async => null,
      persistThemeMode: (_) async {},
    );
    addTearDown(controller.dispose);

    await controller.refresh();

    expect(controller.notificationStatus, SettingsPermissionStatus.unavailable);
    expect(controller.exactAlarmStatus, SettingsPermissionStatus.unavailable);
    expect(controller.callbackLinkStatus, SettingsPermissionStatus.allowed);
    expect(controller.versionStatus, SettingsVersionStatus.available);
    expect(
      controller.appVersion,
      const AppVersion(version: '9.8.7', buildNumber: '6543'),
    );
  });

  test(
    'newest refresh wins when an older permission read finishes last',
    () async {
      final first = Completer<NotificationPermissionStatus>();
      final second = Completer<NotificationPermissionStatus>();
      final notifications = _QueuedNotificationSettings([
        first.future,
        second.future,
      ]);
      final controller = SettingsController(
        initialProfile: profile,
        initialThemeMode: ThemeMode.system,
        isAndroid: false,
        notificationSettings: notifications,
        callbackLinkSettings: _CallbackSettings(enabled: true),
        appVersionProvider: _VersionProvider(
          const AppVersion(version: '1.2.3', buildNumber: '45'),
        ),
        editProfile: () async => null,
        persistThemeMode: (_) async {},
      );
      addTearDown(controller.dispose);

      final olderRefresh = controller.refresh();
      final newerRefresh = controller.refresh();
      second.complete(
        const NotificationPermissionStatus(
          notificationsAllowed: false,
          exactAlarmsAllowed: null,
        ),
      );
      await newerRefresh;
      expect(controller.notificationStatus, SettingsPermissionStatus.needed);

      first.complete(
        const NotificationPermissionStatus(
          notificationsAllowed: true,
          exactAlarmsAllowed: null,
        ),
      );
      await olderRefresh;

      expect(controller.notificationStatus, SettingsPermissionStatus.needed);
    },
  );

  test('a pending refresh does not publish after dispose', () async {
    final pending = Completer<NotificationPermissionStatus>();
    final controller = SettingsController(
      initialProfile: profile,
      initialThemeMode: ThemeMode.system,
      isAndroid: false,
      notificationSettings: _QueuedNotificationSettings([pending.future]),
      callbackLinkSettings: _CallbackSettings(enabled: true),
      appVersionProvider: _VersionProvider(
        const AppVersion(version: '1.2.3', buildNumber: '45'),
      ),
      editProfile: () async => null,
      persistThemeMode: (_) async {},
    );

    final refresh = controller.refresh();
    controller.dispose();
    pending.complete(
      const NotificationPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: null,
      ),
    );

    await expectLater(refresh, completes);
  });
}

class _NotificationSettings implements NotificationPermissionSettings {
  _NotificationSettings({this.statusError});

  final Object? statusError;

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    if (statusError case final error?) throw error;
    return const NotificationPermissionStatus(
      notificationsAllowed: true,
      exactAlarmsAllowed: true,
    );
  }

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<void> openNotificationSettings() async {}
}

class _QueuedNotificationSettings implements NotificationPermissionSettings {
  _QueuedNotificationSettings(this.responses);

  final List<Future<NotificationPermissionStatus>> responses;
  int _index = 0;

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() =>
      responses[_index++];

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<void> openNotificationSettings() async {}
}

class _CallbackSettings implements CallbackLinkSettings {
  _CallbackSettings({required this.enabled});

  final bool enabled;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> open() async {}
}

class _VersionProvider implements AppVersionProvider {
  _VersionProvider(this.version);

  final AppVersion version;

  @override
  Future<AppVersion> getAppVersion() async => version;
}

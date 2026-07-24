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
    'notification allowed remains visible when exact alarm is unavailable',
    () async {
      final controller = SettingsController(
        initialProfile: profile,
        initialThemeMode: ThemeMode.system,
        isAndroid: true,
        notificationSettings: _NotificationSettings(
          status: const NotificationPermissionStatus.android(
            notificationsAllowed: true,
            exactAlarmsAllowed: null,
          ),
        ),
        callbackLinkSettings: _CallbackSettings(enabled: true),
        appVersionProvider: _VersionProvider(
          const AppVersion(version: '1.2.3', buildNumber: '45'),
        ),
        editProfile: () async => null,
        persistThemeMode: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.notificationStatus, SettingsPermissionStatus.allowed);
      expect(controller.exactAlarmStatus, SettingsPermissionStatus.unavailable);
    },
  );

  test(
    'exact alarm allowed remains visible when notification is unavailable',
    () async {
      final controller = SettingsController(
        initialProfile: profile,
        initialThemeMode: ThemeMode.system,
        isAndroid: true,
        notificationSettings: _NotificationSettings(
          status: const NotificationPermissionStatus.android(
            notificationsAllowed: null,
            exactAlarmsAllowed: true,
          ),
        ),
        callbackLinkSettings: _CallbackSettings(enabled: true),
        appVersionProvider: _VersionProvider(
          const AppVersion(version: '1.2.3', buildNumber: '45'),
        ),
        editProfile: () async => null,
        persistThemeMode: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(
        controller.notificationStatus,
        SettingsPermissionStatus.unavailable,
      );
      expect(controller.exactAlarmStatus, SettingsPermissionStatus.allowed);
    },
  );

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
        const NotificationPermissionStatus.notApplicable(
          notificationsAllowed: false,
        ),
      );
      await newerRefresh;
      expect(controller.notificationStatus, SettingsPermissionStatus.needed);

      first.complete(
        const NotificationPermissionStatus.notApplicable(
          notificationsAllowed: true,
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
      const NotificationPermissionStatus.notApplicable(
        notificationsAllowed: true,
      ),
    );

    await expectLater(refresh, completes);
  });

  test(
    'profile editing ignores overlapping requests until completion',
    () async {
      const changedProfile = UserProfile(
        name: '김스칼라',
        region: CampusRegion.pangyo4f,
        classNumber: 3,
      );
      final result = Completer<UserProfile?>();
      var editCalls = 0;
      final controller = SettingsController(
        initialProfile: profile,
        initialThemeMode: ThemeMode.system,
        isAndroid: false,
        notificationSettings: _NotificationSettings(),
        callbackLinkSettings: _CallbackSettings(enabled: true),
        appVersionProvider: _VersionProvider(
          const AppVersion(version: '1.2.3', buildNumber: '45'),
        ),
        editProfile: () {
          editCalls += 1;
          return result.future;
        },
        persistThemeMode: (_) async {},
      );
      addTearDown(controller.dispose);

      final firstEdit = controller.editProfile();
      expect(controller.profileEditInProgress, isTrue);
      final overlappingEdit = controller.editProfile();

      await expectLater(overlappingEdit, completion(isNull));
      expect(editCalls, 1);
      expect(controller.profile, same(profile));

      result.complete(changedProfile);
      await expectLater(firstEdit, completion(isNull));

      expect(controller.profile, same(changedProfile));
      expect(controller.profileEditInProgress, isFalse);
    },
  );

  test('cancelled and failed profile edits release the edit guard', () async {
    var shouldFail = false;
    final controller = SettingsController(
      initialProfile: profile,
      initialThemeMode: ThemeMode.system,
      isAndroid: false,
      notificationSettings: _NotificationSettings(),
      callbackLinkSettings: _CallbackSettings(enabled: true),
      appVersionProvider: _VersionProvider(
        const AppVersion(version: '1.2.3', buildNumber: '45'),
      ),
      editProfile: () async {
        if (shouldFail) throw StateError('edit failed');
        return null;
      },
      persistThemeMode: (_) async {},
    );
    addTearDown(controller.dispose);

    expect(await controller.editProfile(), isNull);
    expect(controller.profile, same(profile));
    expect(controller.profileEditInProgress, isFalse);

    shouldFail = true;
    expect(await controller.editProfile(), '사용자 정보를 변경하지 못했습니다.');
    expect(controller.profile, same(profile));
    expect(controller.profileEditInProgress, isFalse);
  });

  test(
    'theme persistence is serialized while the newest choice shows now',
    () async {
      final darkSave = Completer<void>();
      final lightSave = Completer<void>();
      final saveCalls = <ThemeMode>[];
      final appliedThemes = <ThemeMode>[];
      final controller = SettingsController(
        initialProfile: profile,
        initialThemeMode: ThemeMode.system,
        isAndroid: false,
        notificationSettings: _NotificationSettings(),
        callbackLinkSettings: _CallbackSettings(enabled: true),
        appVersionProvider: _VersionProvider(
          const AppVersion(version: '1.2.3', buildNumber: '45'),
        ),
        editProfile: () async => null,
        applyThemeMode: appliedThemes.add,
        persistThemeMode: (mode) {
          saveCalls.add(mode);
          return switch (mode) {
            ThemeMode.dark => darkSave.future,
            ThemeMode.light => lightSave.future,
            ThemeMode.system => Future<void>.value(),
          };
        },
      );
      addTearDown(controller.dispose);

      final firstSelection = controller.selectTheme(ThemeMode.dark);
      await Future<void>.delayed(Duration.zero);
      expect(controller.themeMode, ThemeMode.dark);
      expect(saveCalls, [ThemeMode.dark]);

      final secondSelection = controller.selectTheme(ThemeMode.light);
      await Future<void>.delayed(Duration.zero);
      expect(controller.themeMode, ThemeMode.light);
      expect(appliedThemes, [ThemeMode.dark, ThemeMode.light]);
      expect(saveCalls, [ThemeMode.dark]);

      darkSave.complete();
      await Future<void>.delayed(Duration.zero);
      expect(saveCalls, [ThemeMode.dark, ThemeMode.light]);

      lightSave.complete();
      await expectLater(firstSelection, completion(isNull));
      await expectLater(secondSelection, completion(isNull));
    },
  );

  test(
    'failed theme persistence reports failure and does not revert UI',
    () async {
      final controller = SettingsController(
        initialProfile: profile,
        initialThemeMode: ThemeMode.system,
        isAndroid: false,
        notificationSettings: _NotificationSettings(),
        callbackLinkSettings: _CallbackSettings(enabled: true),
        appVersionProvider: _VersionProvider(
          const AppVersion(version: '1.2.3', buildNumber: '45'),
        ),
        editProfile: () async => null,
        persistThemeMode: (_) async => throw StateError('save failed'),
      );
      addTearDown(controller.dispose);

      expect(
        await controller.selectTheme(ThemeMode.dark),
        '테마 설정을 저장하지 못했습니다.',
      );
      expect(controller.themeMode, ThemeMode.dark);
    },
  );
}

class _NotificationSettings implements NotificationPermissionSettings {
  _NotificationSettings({this.status, this.statusError});

  final NotificationPermissionStatus? status;
  final Object? statusError;

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    if (statusError case final error?) throw error;
    return status ??
        const NotificationPermissionStatus.android(
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

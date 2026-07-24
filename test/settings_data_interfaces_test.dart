import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:skala_attendance/features/schedule/application/notification_scheduler.dart';
import 'package:skala_attendance/features/schedule/data/local_notification_scheduler.dart';
import 'package:skala_attendance/features/schedule/data/android_alarm_platform.dart';
import 'package:skala_attendance/features/schedule/domain/alarm_occurrence.dart';
import 'package:skala_attendance/features/settings/data/package_info_app_version_provider.dart';
import 'package:skala_attendance/features/settings/domain/app_version.dart';

void main() {
  test('Android readiness requires both notification permissions', () async {
    final scheduler = LocalNotificationScheduler(
      permissionPlatform: _FakeNotificationPermissionPlatform(
        status: const NotificationPermissionStatus.android(
          notificationsAllowed: true,
          exactAlarmsAllowed: false,
        ),
      ),
    );

    expect(await scheduler.arePermissionsGranted(), isFalse);
  });

  test('Android readiness also rejects denied notifications', () async {
    final scheduler = LocalNotificationScheduler(
      permissionPlatform: _FakeNotificationPermissionPlatform(
        status: const NotificationPermissionStatus.android(
          notificationsAllowed: false,
          exactAlarmsAllowed: true,
        ),
      ),
    );

    expect(await scheduler.arePermissionsGranted(), isFalse);
  });

  test('Android readiness requires full-screen alarm access', () async {
    final scheduler = LocalNotificationScheduler(
      permissionPlatform: _FakeNotificationPermissionPlatform(
        status: const NotificationPermissionStatus.android(
          notificationsAllowed: true,
          exactAlarmsAllowed: true,
        ),
      ),
      alarmPlatform: _FakeAndroidAlarmPlatform(fullScreenAllowed: false),
      isAndroid: true,
    );

    expect(await scheduler.arePermissionsGranted(), isFalse);
  });

  test(
    'Android keeps notification status when exact alarm lookup fails',
    () async {
      final platform = FlutterNotificationPermissionPlatform(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        isIOS: false,
        readNotificationsAllowed: () async => true,
        readExactAlarmsAllowed: () async {
          throw StateError('exact alarm unavailable');
        },
      );

      final status = await platform.getPermissionStatus();

      expect(status.notificationsAllowed, isTrue);
      expect(status.exactAlarmsAllowed, isNull);
      expect(status.exactAlarmsApplicable, isTrue);
      expect(status.arePermissionsGranted, isFalse);
    },
  );

  test(
    'Android keeps exact alarm status when notification lookup fails',
    () async {
      final platform = FlutterNotificationPermissionPlatform(
        FlutterLocalNotificationsPlugin(),
        isAndroid: true,
        isIOS: false,
        readNotificationsAllowed: () async {
          throw StateError('notifications unavailable');
        },
        readExactAlarmsAllowed: () async => true,
      );

      final status = await platform.getPermissionStatus();

      expect(status.notificationsAllowed, isNull);
      expect(status.exactAlarmsAllowed, isTrue);
      expect(status.exactAlarmsApplicable, isTrue);
      expect(status.arePermissionsGranted, isFalse);
    },
  );

  test(
    'iOS exact alarms are not applicable while notifications stay ready',
    () {
      const status = NotificationPermissionStatus.notApplicable(
        notificationsAllowed: true,
      );

      expect(status.exactAlarmsApplicable, isFalse);
      expect(status.arePermissionsGranted, isTrue);
    },
  );

  test('Android unknown exact alarm state remains fail-closed', () {
    const status = NotificationPermissionStatus.android(
      notificationsAllowed: true,
      exactAlarmsAllowed: null,
    );

    expect(status.exactAlarmsApplicable, isTrue);
    expect(status.arePermissionsGranted, isFalse);
  });

  test('package version provider maps installed package metadata', () async {
    final provider = PackageInfoAppVersionProvider(
      loadPackageInfo: () async => PackageInfo(
        appName: 'SKALA 출결 도우미',
        packageName: 'com.ddhhyy.skala_attendance',
        version: '9.8.7',
        buildNumber: '6543',
      ),
    );

    expect(
      await provider.getAppVersion(),
      const AppVersion(version: '9.8.7', buildNumber: '6543'),
    );
  });
}

class _FakeNotificationPermissionPlatform
    implements NotificationPermissionPlatform {
  _FakeNotificationPermissionPlatform({required this.status});

  final NotificationPermissionStatus status;

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async => status;

  @override
  Future<void> openExactAlarmSettings() async {}

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<bool> requestPermissions() async => status.arePermissionsGranted;
}

class _FakeAndroidAlarmPlatform implements AndroidAlarmPlatform {
  _FakeAndroidAlarmPlatform({required this.fullScreenAllowed});

  final bool fullScreenAllowed;

  @override
  Future<bool?> canUseFullScreenIntent() async => fullScreenAllowed;

  @override
  Future<void> initialize(AlarmActionCallback onAction) async {}

  @override
  Future<void> openFullScreenIntentSettings() async {}

  @override
  Future<void> sync(List<AlarmOccurrence> occurrences) async {}

  @override
  Future<String?> takeLaunchPayload() async => null;
}

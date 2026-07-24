import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:skala_attendance/features/schedule/application/notification_scheduler.dart';
import 'package:skala_attendance/features/schedule/data/local_notification_scheduler.dart';
import 'package:skala_attendance/features/settings/data/package_info_app_version_provider.dart';
import 'package:skala_attendance/features/settings/domain/app_version.dart';

void main() {
  test('Android readiness requires both notification permissions', () async {
    final scheduler = LocalNotificationScheduler(
      permissionPlatform: _FakeNotificationPermissionPlatform(
        status: const NotificationPermissionStatus(
          notificationsAllowed: true,
          exactAlarmsAllowed: false,
        ),
      ),
    );

    expect(await scheduler.arePermissionsGranted(), isFalse);
  });

  test(
    'iOS exact alarms are not applicable while notifications stay ready',
    () {
      const status = NotificationPermissionStatus(
        notificationsAllowed: true,
        exactAlarmsAllowed: null,
      );

      expect(status.exactAlarmsApplicable, isFalse);
      expect(status.arePermissionsGranted, isTrue);
    },
  );

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

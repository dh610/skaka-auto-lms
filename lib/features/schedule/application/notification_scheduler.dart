import '../domain/attendance_schedule.dart';
import 'package:flutter/foundation.dart';

/// The independent notification permissions a settings screen can show.
///
/// [exactAlarmsAllowed] is `null` where exact alarms do not apply, including
/// iOS. The existing setup readiness remains strict on Android: it requires
/// both values to be allowed.
class NotificationPermissionStatus {
  const NotificationPermissionStatus({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
  });

  final bool notificationsAllowed;
  final bool? exactAlarmsAllowed;

  bool get exactAlarmsApplicable => exactAlarmsAllowed != null;

  bool get arePermissionsGranted =>
      notificationsAllowed && (exactAlarmsAllowed ?? true);
}

/// Platform-independent notification settings operations for later settings
/// presentation and application layers.
abstract interface class NotificationPermissionSettings {
  Future<NotificationPermissionStatus> getPermissionStatus();

  Future<void> openNotificationSettings();

  /// Does nothing on platforms where exact alarms are not applicable.
  Future<void> openExactAlarmSettings();
}

abstract interface class NotificationScheduler {
  ValueListenable<String?> get tapPayload;

  void consumeTap();

  Future<void> initialize();

  Future<bool> arePermissionsGranted();

  Future<bool> requestPermissions();

  Future<void> openPermissionSettings();

  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now});
}

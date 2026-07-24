import '../domain/attendance_schedule.dart';
import 'package:flutter/foundation.dart';

/// The independent notification permissions a settings screen can show.
///
/// A nullable permission value means that the platform status could not be
/// read. [exactAlarmsApplicable] distinguishes an unavailable Android exact
/// alarm read from platforms such as iOS where exact alarms do not apply.
///
/// Existing setup readiness remains strict on Android: both applicable
/// permissions must be known and allowed.
class NotificationPermissionStatus {
  const NotificationPermissionStatus.android({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
  }) : exactAlarmsApplicable = true;

  const NotificationPermissionStatus.notApplicable({
    required this.notificationsAllowed,
  }) : exactAlarmsAllowed = null,
       exactAlarmsApplicable = false;

  final bool? notificationsAllowed;
  final bool? exactAlarmsAllowed;
  final bool exactAlarmsApplicable;

  bool get arePermissionsGranted =>
      notificationsAllowed == true &&
      (!exactAlarmsApplicable || exactAlarmsAllowed == true);
}

/// Platform-independent notification settings operations for later settings
/// presentation and application layers.
abstract interface class NotificationPermissionSettings {
  Future<NotificationPermissionStatus> getPermissionStatus();

  Future<void> openNotificationSettings();

  /// Does nothing on platforms where exact alarms are not applicable.
  Future<void> openExactAlarmSettings();
}

abstract interface class FullScreenAlarmPermissionSettings {
  Future<bool?> canUseFullScreenIntent();

  Future<void> openFullScreenIntentSettings();
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

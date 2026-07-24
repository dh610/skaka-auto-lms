import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../application/notification_scheduler.dart';
import '../domain/attendance_schedule.dart';
import '../domain/schedule_reminder.dart';

class LocalNotificationScheduler
    implements NotificationScheduler, NotificationPermissionSettings {
  LocalNotificationScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationPermissionPlatform? permissionPlatform,
  }) : this._(plugin ?? FlutterLocalNotificationsPlugin(), permissionPlatform);

  LocalNotificationScheduler._(
    this._plugin,
    NotificationPermissionPlatform? permissionPlatform,
  ) : _permissionPlatform =
          permissionPlatform ?? FlutterNotificationPermissionPlatform(_plugin);

  static const _channelId = 'attendance_schedule_reminders';
  static const _channelName = '출결 일정 알림';
  static const _channelDescription = '설정한 입실·퇴실·외출·복귀 일정을 알려줍니다.';

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationPermissionPlatform _permissionPlatform;
  final ValueNotifier<String?> _tapPayload = ValueNotifier(null);
  bool _initialized = false;

  @override
  ValueListenable<String?> get tapPayload => _tapPayload;

  @override
  void consumeTap() {
    _tapPayload.value = null;
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload case final payload? when payload.isNotEmpty) {
          _tapPayload.value = payload;
        }
      },
    );
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchPayload != null &&
        launchPayload.isNotEmpty) {
      _tapPayload.value = launchPayload;
    }
    _initialized = true;
  }

  @override
  Future<bool> arePermissionsGranted() async {
    return (await getPermissionStatus()).arePermissionsGranted;
  }

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    return _permissionPlatform.getPermissionStatus();
  }

  @override
  Future<bool> requestPermissions() async {
    await initialize();
    return _permissionPlatform.requestPermissions();
  }

  @override
  Future<void> openPermissionSettings() async {
    await openNotificationSettings();
  }

  @override
  Future<void> openNotificationSettings() =>
      _permissionPlatform.openNotificationSettings();

  @override
  Future<void> openExactAlarmSettings() =>
      _permissionPlatform.openExactAlarmSettings();

  @override
  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now}) async {
    await initialize();
    await _plugin.cancelAllPendingNotifications();
    final reminders = ScheduleReminderPlanner.plan(
      schedules,
      now: now ?? DateTime.now(),
    );
    var mode = AndroidScheduleMode.exactAllowWhileIdle;
    if (Platform.isAndroid) {
      final canScheduleExact = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.canScheduleExactNotifications();
      if (canScheduleExact == false) {
        mode = AndroidScheduleMode.inexactAllowWhileIdle;
      }
    }
    for (var index = 0; index < reminders.length; index++) {
      final reminder = reminders[index];
      await _plugin.zonedSchedule(
        id: 1000 + index,
        title: '${reminder.schedule.action.label} 시간입니다',
        body: '알림을 눌러 Google 인증 후 출결을 확인하세요.',
        scheduledDate: tz.TZDateTime.from(reminder.dateTime, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: mode,
        payload: jsonEncode({
          'scheduleId': reminder.schedule.id,
          'action': reminder.schedule.action.name,
          'scheduledAt': reminder.dateTime.toIso8601String(),
        }),
      );
    }
    return reminders.length;
  }
}

/// Data-layer platform adapter for notification permissions and system
/// settings. It keeps plugin and MethodChannel calls out of presentation code.
abstract interface class NotificationPermissionPlatform {
  Future<NotificationPermissionStatus> getPermissionStatus();

  Future<bool> requestPermissions();

  Future<void> openNotificationSettings();

  Future<void> openExactAlarmSettings();
}

class FlutterNotificationPermissionPlatform
    implements NotificationPermissionPlatform {
  FlutterNotificationPermissionPlatform(
    this._plugin, {
    bool? isAndroid,
    bool? isIOS,
  }) : _isAndroid = isAndroid ?? Platform.isAndroid,
       _isIOS = isIOS ?? Platform.isIOS;

  static const _settingsChannel = MethodChannel('skala_attendance/settings');

  final FlutterLocalNotificationsPlugin _plugin;
  final bool _isAndroid;
  final bool _isIOS;

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    if (_isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return NotificationPermissionStatus(
        notificationsAllowed: await android?.areNotificationsEnabled() ?? false,
        exactAlarmsAllowed:
            await android?.canScheduleExactNotifications() ?? false,
      );
    }
    if (_isIOS) {
      final permissions = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return NotificationPermissionStatus(
        notificationsAllowed: permissions?.isEnabled ?? false,
        exactAlarmsAllowed: null,
      );
    }
    return const NotificationPermissionStatus(
      notificationsAllowed: false,
      exactAlarmsAllowed: null,
    );
  }

  @override
  Future<bool> requestPermissions() async {
    if (_isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notificationsAllowed =
          await android?.requestNotificationsPermission() ?? false;
      var exactAlarmsAllowed =
          await android?.canScheduleExactNotifications() ?? false;
      if (!exactAlarmsAllowed) {
        exactAlarmsAllowed =
            await android?.requestExactAlarmsPermission() ?? false;
      }
      return notificationsAllowed && exactAlarmsAllowed;
    }
    if (_isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<void> openNotificationSettings() async {
    if (_isAndroid) {
      await _settingsChannel.invokeMethod<void>('openNotificationSettings');
      return;
    }
    if (_isIOS) {
      final opened = await launchUrl(
        Uri.parse('app-settings:'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('iOS 알림 설정 화면을 열 수 없습니다.');
    }
  }

  @override
  Future<void> openExactAlarmSettings() async {
    if (!_isAndroid) return;
    await _settingsChannel.invokeMethod<void>('openExactAlarmSettings');
  }
}

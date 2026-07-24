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
import '../domain/alarm_occurrence.dart';
import '../domain/schedule_reminder.dart';
import 'android_alarm_platform.dart';

class LocalNotificationScheduler
    implements
        NotificationScheduler,
        NotificationPermissionSettings,
        FullScreenAlarmPermissionSettings {
  LocalNotificationScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationPermissionPlatform? permissionPlatform,
    AndroidAlarmPlatform? alarmPlatform,
    bool? isAndroid,
  }) : this._(
         plugin ?? FlutterLocalNotificationsPlugin(),
         permissionPlatform,
         alarmPlatform,
         isAndroid ?? Platform.isAndroid,
       );

  LocalNotificationScheduler._(
    this._plugin,
    NotificationPermissionPlatform? permissionPlatform,
    AndroidAlarmPlatform? alarmPlatform,
    this._isAndroid,
  ) : _permissionPlatform =
          permissionPlatform ?? FlutterNotificationPermissionPlatform(_plugin),
      _alarmPlatform =
          alarmPlatform ??
          (_isAndroid ? MethodChannelAndroidAlarmPlatform() : null);

  static const _channelId = 'attendance_schedule_reminders';
  static const _channelName = '출결 일정 알림';
  static const _channelDescription = '설정한 입실·퇴실·외출·복귀 일정을 알려줍니다.';

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationPermissionPlatform _permissionPlatform;
  final AndroidAlarmPlatform? _alarmPlatform;
  final bool _isAndroid;
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
    if (_isAndroid) {
      await _alarmPlatform?.initialize((payload) {
        _tapPayload.value = payload;
      });
      final alarmPayload = await _alarmPlatform?.takeLaunchPayload();
      if (alarmPayload != null && alarmPayload.isNotEmpty) {
        _tapPayload.value = alarmPayload;
      }
    }
    _initialized = true;
  }

  @override
  Future<bool> arePermissionsGranted() async {
    final notificationPermissions =
        (await getPermissionStatus()).arePermissionsGranted;
    if (!notificationPermissions || !_isAndroid) {
      return notificationPermissions;
    }
    return await canUseFullScreenIntent() == true;
  }

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    return _permissionPlatform.getPermissionStatus();
  }

  @override
  Future<bool> requestPermissions() async {
    await initialize();
    final notificationPermissions = await _permissionPlatform
        .requestPermissions();
    if (!notificationPermissions || !_isAndroid) {
      return notificationPermissions;
    }
    if (await canUseFullScreenIntent() == true) return true;
    await openFullScreenIntentSettings();
    return false;
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
  Future<bool?> canUseFullScreenIntent() async {
    if (!_isAndroid) return true;
    try {
      return await _alarmPlatform?.canUseFullScreenIntent();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openFullScreenIntentSettings() async {
    if (!_isAndroid) return;
    await _alarmPlatform?.openFullScreenIntentSettings();
  }

  @override
  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now}) async {
    await initialize();
    await _plugin.cancelAllPendingNotifications();
    final reminders = ScheduleReminderPlanner.plan(
      schedules,
      now: now ?? DateTime.now(),
    );
    if (_isAndroid) {
      await _alarmPlatform?.sync(
        reminders
            .map(
              (reminder) => AlarmOccurrence(
                schedule: reminder.schedule,
                scheduledAt: reminder.dateTime,
              ),
            )
            .toList(),
      );
      return reminders.length;
    }
    var mode = AndroidScheduleMode.exactAllowWhileIdle;
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
    this.readNotificationsAllowed,
    this.readExactAlarmsAllowed,
  }) : _isAndroid = isAndroid ?? Platform.isAndroid,
       _isIOS = isIOS ?? Platform.isIOS;

  static const _settingsChannel = MethodChannel('skala_attendance/settings');

  final FlutterLocalNotificationsPlugin _plugin;
  final bool _isAndroid;
  final bool _isIOS;
  final Future<bool?> Function()? readNotificationsAllowed;
  final Future<bool?> Function()? readExactAlarmsAllowed;

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    if (_isAndroid) {
      final android =
          readNotificationsAllowed == null || readExactAlarmsAllowed == null
          ? _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
          : null;
      final notificationsAllowed = await _readPermissionStatus(
        readNotificationsAllowed ??
            () async => await android?.areNotificationsEnabled() ?? false,
      );
      final exactAlarmsAllowed = await _readPermissionStatus(
        readExactAlarmsAllowed ??
            () async => await android?.canScheduleExactNotifications() ?? false,
      );
      return NotificationPermissionStatus.android(
        notificationsAllowed: notificationsAllowed,
        exactAlarmsAllowed: exactAlarmsAllowed,
      );
    }
    if (_isIOS) {
      final notificationsAllowed = await _readPermissionStatus(
        readNotificationsAllowed ??
            () async {
              final permissions = await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.checkPermissions();
              return permissions?.isEnabled ?? false;
            },
      );
      return NotificationPermissionStatus.notApplicable(
        notificationsAllowed: notificationsAllowed,
      );
    }
    return const NotificationPermissionStatus.notApplicable(
      notificationsAllowed: false,
    );
  }

  Future<bool?> _readPermissionStatus(
    Future<bool?> Function() readStatus,
  ) async {
    try {
      return await readStatus();
    } catch (_) {
      return null;
    }
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

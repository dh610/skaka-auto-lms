import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../application/notification_scheduler.dart';
import '../domain/attendance_schedule.dart';
import '../domain/schedule_reminder.dart';

class LocalNotificationScheduler implements NotificationScheduler {
  LocalNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'attendance_schedule_reminders';
  static const _channelName = '출결 일정 알림';
  static const _channelDescription = '설정한 입실·퇴실·외출·복귀 일정을 알려줍니다.';

  final FlutterLocalNotificationsPlugin _plugin;
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
    await initialize();
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notificationsAllowed =
          await android?.areNotificationsEnabled() ?? true;
      final exactAllowed =
          await android?.canScheduleExactNotifications() ?? true;
      return notificationsAllowed && exactAllowed;
    }
    if (Platform.isIOS) {
      final permissions = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return permissions?.isEnabled ?? false;
    }
    return false;
  }

  @override
  Future<bool> requestPermissions() async {
    await initialize();
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notificationAllowed =
          await android?.requestNotificationsPermission() ?? true;
      var exactAllowed = await android?.canScheduleExactNotifications() ?? true;
      if (!exactAllowed) {
        exactAllowed = await android?.requestExactAlarmsPermission() ?? false;
      }
      return notificationAllowed && exactAllowed;
    }
    if (Platform.isIOS) {
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

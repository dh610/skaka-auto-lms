import 'package:flutter/foundation.dart';

import '../data/schedule_store.dart';
import '../domain/attendance_schedule.dart';
import '../domain/training_calendar.dart';
import 'notification_scheduler.dart';

class ScheduleController extends ChangeNotifier {
  ScheduleController(this._store, [this._notificationScheduler]);

  final ScheduleStore _store;
  final NotificationScheduler? _notificationScheduler;
  List<AttendanceSchedule> _schedules = [];
  bool _loading = true;
  String _notificationMessage = '알림 권한을 설정하면 지정 시각에 안내합니다.';
  int _pendingNotificationCount = 0;

  List<AttendanceSchedule> get schedules => List.unmodifiable(_schedules);
  bool get loading => _loading;
  String get notificationMessage => _notificationMessage;
  int get pendingNotificationCount => _pendingNotificationCount;

  Future<void> load() async {
    _schedules = await _store.load();
    _sort();
    _loading = false;
    await _syncNotifications();
    notifyListeners();
  }

  List<AttendanceSchedule> schedulesFor(DateTime date) {
    if (!TrainingCalendar.isWithinCourse(date)) return [];
    return _schedules.where((schedule) {
      if (!schedule.matches(date)) return false;
      return schedule.recurrence == ScheduleRecurrence.once ||
          !schedule.excludePublicHolidays ||
          !TrainingCalendar.isPublicHoliday(date);
    }).toList();
  }

  Future<void> saveSchedule(AttendanceSchedule schedule) async {
    final index = _schedules.indexWhere((item) => item.id == schedule.id);
    if (index == -1) {
      _schedules.add(schedule);
    } else {
      _schedules[index] = schedule;
    }
    await _persist(requestPermission: true);
  }

  Future<void> setEnabled(AttendanceSchedule schedule, bool enabled) async {
    await saveSchedule(schedule.copyWith(enabled: enabled));
  }

  Future<void> delete(AttendanceSchedule schedule) async {
    _schedules.removeWhere((item) => item.id == schedule.id);
    await _persist();
  }

  Future<void> configureNotifications() async {
    final scheduler = _notificationScheduler;
    if (scheduler == null) return;
    try {
      final exact = await scheduler.requestPermissions();
      await _syncNotifications();
      _notificationMessage = exact
          ? '정확한 알림이 설정되었습니다.'
          : '정확한 알림 권한이 없어 알림 시각이 다소 늦어질 수 있습니다.';
    } catch (error) {
      _notificationMessage = '알림 설정 실패: $error';
    }
    notifyListeners();
  }

  Future<void> _persist({bool requestPermission = false}) async {
    _sort();
    await _store.save(_schedules);
    if (requestPermission) {
      await configureNotifications();
    } else {
      await _syncNotifications();
    }
    notifyListeners();
  }

  Future<void> _syncNotifications() async {
    final scheduler = _notificationScheduler;
    if (scheduler == null) return;
    try {
      _pendingNotificationCount = await scheduler.sync(_schedules);
      if (_pendingNotificationCount > 0) {
        _notificationMessage = '예정된 알림 $_pendingNotificationCount건이 등록되어 있습니다.';
      } else {
        _notificationMessage = '앞으로 예정된 알림이 없습니다.';
      }
    } catch (error) {
      _notificationMessage = '알림 예약 실패: $error';
    }
  }

  void _sort() {
    _schedules.sort(
      (a, b) => a.minutesSinceMidnight.compareTo(b.minutesSinceMidnight),
    );
  }
}

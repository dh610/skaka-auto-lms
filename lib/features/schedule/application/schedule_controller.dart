import 'package:flutter/foundation.dart';

import '../data/schedule_store.dart';
import '../domain/attendance_schedule.dart';

class ScheduleController extends ChangeNotifier {
  ScheduleController(this._store);

  final ScheduleStore _store;
  List<AttendanceSchedule> _schedules = [];
  bool _loading = true;

  List<AttendanceSchedule> get schedules => List.unmodifiable(_schedules);
  bool get loading => _loading;

  Future<void> load() async {
    _schedules = await _store.load();
    _sort();
    _loading = false;
    notifyListeners();
  }

  List<AttendanceSchedule> schedulesFor(DateTime date) {
    return _schedules.where((schedule) => schedule.occursOn(date)).toList();
  }

  Future<void> saveSchedule(AttendanceSchedule schedule) async {
    final index = _schedules.indexWhere((item) => item.id == schedule.id);
    if (index == -1) {
      _schedules.add(schedule);
    } else {
      _schedules[index] = schedule;
    }
    await _persist();
  }

  Future<void> setEnabled(AttendanceSchedule schedule, bool enabled) async {
    await saveSchedule(schedule.copyWith(enabled: enabled));
  }

  Future<void> delete(AttendanceSchedule schedule) async {
    _schedules.removeWhere((item) => item.id == schedule.id);
    await _persist();
  }

  Future<void> _persist() async {
    _sort();
    await _store.save(_schedules);
    notifyListeners();
  }

  void _sort() {
    _schedules.sort(
      (a, b) => a.minutesSinceMidnight.compareTo(b.minutesSinceMidnight),
    );
  }
}

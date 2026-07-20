import '../domain/attendance_schedule.dart';
import 'package:flutter/foundation.dart';

abstract interface class NotificationScheduler {
  ValueListenable<String?> get tapPayload;

  void consumeTap();

  Future<void> initialize();

  Future<bool> requestPermissions();

  Future<int> sync(List<AttendanceSchedule> schedules, {DateTime? now});
}

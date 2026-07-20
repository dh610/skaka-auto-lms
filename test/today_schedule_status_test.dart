import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/features/attendance/data/attendance_completion_store.dart';
import 'package:skala_attendance/features/attendance/domain/today_schedule_status.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';

void main() {
  const schedule = AttendanceSchedule(
    id: 'check-in',
    action: AttendanceAction.checkIn,
    hour: 9,
    minute: 0,
    weekdays: {DateTime.monday},
    enabled: true,
  );

  test('future schedule is upcoming', () {
    expect(
      statusForTodaySchedule(schedule, now: DateTime(2026, 7, 20, 8, 59)),
      TodayScheduleStatus.upcoming,
    );
  });

  test('past schedule without matching attendance is overdue', () {
    expect(
      statusForTodaySchedule(schedule, now: DateTime(2026, 7, 20, 9, 1)),
      TodayScheduleStatus.overdue,
    );
  });

  test('server attendance alone does not mark a schedule completed', () {
    expect(
      statusForTodaySchedule(schedule, now: DateTime(2026, 7, 20, 9, 1)),
      TodayScheduleStatus.overdue,
    );
  });

  test('persisted completion marks a schedule completed after restart', () {
    expect(
      statusForTodaySchedule(
        schedule,
        now: DateTime(2026, 7, 20, 9, 1),
        persistedCompleted: true,
      ),
      TodayScheduleStatus.completed,
    );
  });

  test(
    'completion store restores only timestamps from the current date',
    () async {
      SharedPreferences.setMockInitialValues({
        'attendance.completedAt': jsonEncode({
          AttendanceCompletionStore.occurrenceKey(
            'today-check-in',
            DateTime(2026, 7, 20, 9),
          ): '2026-07-20T09:00:01.000',
          AttendanceCompletionStore.occurrenceKey(
            'yesterday-check-out',
            DateTime(2026, 7, 19, 17, 50),
          ): '2026-07-19T17:50:01.000',
        }),
      });
      final store = AttendanceCompletionStore();

      final completed = await store.loadFor(DateTime(2026, 7, 20, 12));

      expect(completed.keys, {
        AttendanceCompletionStore.occurrenceKey(
          'today-check-in',
          DateTime(2026, 7, 20, 9),
        ),
      });
    },
  );
}

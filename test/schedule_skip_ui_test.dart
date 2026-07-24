import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/features/schedule/application/schedule_controller.dart';
import 'package:skala_attendance/features/schedule/data/schedule_store.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';
import 'package:skala_attendance/features/schedule/presentation/schedule_edit_screen.dart';
import 'package:skala_attendance/features/schedule/presentation/schedule_list_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('disabled recurring alarm stays editable and can auto resume', (
    tester,
  ) async {
    final store = ScheduleStore();
    const schedule = AttendanceSchedule(
      id: 'disabled-recurring',
      action: AttendanceAction.checkIn,
      hour: 9,
      minute: 0,
      weekdays: {1, 2, 3, 4, 5},
      enabled: false,
    );
    await store.save([schedule]);
    final controller = ScheduleController(store);
    await controller.load();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ScheduleListScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('부터 다시 켜기'), findsOneWidget);
    await tester.tap(find.textContaining('오전 9:00 · 입실'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('부터 다시 켜기'));
    await tester.pumpAndSettle();

    expect(controller.schedules.single.enabled, isTrue);
    expect(controller.schedules.single.skippedOccurrenceAt, isNotNull);
    expect(find.textContaining('자동으로 다시 켜집니다'), findsOneWidget);
  });
}

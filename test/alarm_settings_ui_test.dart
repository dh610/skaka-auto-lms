import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skala_attendance/features/schedule/domain/alarm_settings.dart';
import 'package:skala_attendance/features/schedule/presentation/schedule_edit_screen.dart';

void main() {
  testWidgets('schedule editor exposes and updates alarm settings', (
    tester,
  ) async {
    AlarmSound? requestedSound;
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleEditScreen(
          initialAlarmSettings: const AlarmSettings(
            volumePercent: 70,
            snoozeMinutes: 10,
            maximumSnoozeCount: null,
          ),
          onPickAlarmSound: (current) async {
            requestedSound = current;
            return const AlarmSound(
              uri: 'content://alarm/morning',
              label: 'Morning',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('알람 설정'), 300);
    expect(find.text('알람 설정'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('시스템 기본 알람음'), 200);
    await tester.ensureVisible(find.text('시스템 기본 알람음'));
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('시스템 기본 알람음'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('10분 · 제한 없음'), findsOneWidget);
    expect(find.text('다시 알림'), findsWidgets);

    await tester.tap(
      find.ancestor(
        of: find.text('시스템 기본 알람음'),
        matching: find.byType(ListTile),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedSound, const AlarmSound.systemDefault());
    expect(find.text('Morning'), findsOneWidget);
  });
}

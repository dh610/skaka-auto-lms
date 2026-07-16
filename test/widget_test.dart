import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skala_attendance/app/app.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';
import 'package:skala_attendance/features/profile/presentation/profile_setup_screen.dart';
import 'package:skala_attendance/features/schedule/presentation/schedule_edit_screen.dart';

void main() {
  test('campus regions expose only their valid classes', () {
    expect(CampusRegion.pangyo4f.classNumbers, [1, 2, 3, 4, 5]);
    expect(CampusRegion.pangyo5f.classNumbers, [6, 7, 8, 9, 10]);
  });

  testWidgets('first launch asks for user information', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSetupScreen(onInitialSave: (_) async {})),
    );

    expect(find.text('사용자 정보 설정'), findsOneWidget);
    expect(find.text('이름'), findsOneWidget);
    expect(find.text('지역'), findsOneWidget);
    expect(find.text('반'), findsOneWidget);
    expect(find.text('저장'), findsOneWidget);
  });

  testWidgets('selecting 5F offers classes 6 through 10', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSetupScreen(onInitialSave: (_) async {})),
    );

    await tester.tap(find.text('지역'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('판교캠퍼스 5F').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('반'));
    await tester.pumpAndSettle();

    for (var number = 6; number <= 10; number++) {
      expect(find.text('$number반'), findsOneWidget);
    }
    expect(find.text('5반'), findsNothing);
  });

  testWidgets('saved user can open the profile editing screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile.name': '윤동현',
      'profile.region': 'P2',
      'profile.classNumber': 8,
    });
    await tester.pumpWidget(const SkalaAttendanceApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('사용자 정보 변경'));
    await tester.pumpAndSettle();

    expect(find.text('사용자 정보 수정'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '윤동현'), findsOneWidget);
  });

  testWidgets('schedule editor switches between weekly and one-time modes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));

    expect(find.text('공휴일 제외'), findsOneWidget);
    await tester.tap(find.text('날짜 지정'));
    await tester.pumpAndSettle();

    expect(find.text('실행 날짜'), findsOneWidget);
    expect(find.text('공휴일 제외'), findsNothing);
  });

  testWidgets('weekly editor shows holidays matching selected weekdays', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleEditScreen()));

    await tester.tap(find.text('제외되는 공휴일 보기'));
    await tester.pumpAndSettle();

    expect(find.text('제외되는 공휴일'), findsOneWidget);
    expect(
      find.text('평일 일정과 겹치는 공휴일입니다(2026.07.14~2026.12.18 기준)'),
      findsOneWidget,
    );
    expect(find.text('제헌절'), findsOneWidget);
    expect(find.text('대체공휴일(광복절)'), findsOneWidget);
    expect(find.text('광복절'), findsNothing);
  });
}

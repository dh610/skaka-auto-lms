import 'package:flutter_test/flutter_test.dart';
import 'package:skala_attendance/features/attendance/domain/action_confirmation_policy.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';

void main() {
  test('check-in and return do not require confirmation', () {
    expect(requiresAttendanceConfirmation(AttendanceAction.checkIn), isFalse);
    expect(
      requiresAttendanceConfirmation(AttendanceAction.returnFromLeave),
      isFalse,
    );
  });

  test('leave always requires confirmation', () {
    expect(
      requiresAttendanceConfirmation(
        AttendanceAction.leave,
        now: DateTime(2026, 7, 16, 18),
      ),
      isTrue,
    );
  });

  test('check-out requires confirmation only before 17:50', () {
    expect(
      requiresAttendanceConfirmation(
        AttendanceAction.checkOut,
        now: DateTime(2026, 7, 16, 17, 49),
      ),
      isTrue,
    );
    expect(
      requiresAttendanceConfirmation(
        AttendanceAction.checkOut,
        now: DateTime(2026, 7, 16, 17, 50),
      ),
      isFalse,
    );
    expect(
      requiresAttendanceConfirmation(
        AttendanceAction.checkOut,
        now: DateTime(2026, 7, 16, 18),
      ),
      isFalse,
    );
  });

  test('confirmation messages explain leave and early check-out risks', () {
    expect(
      attendanceConfirmationMessage(AttendanceAction.leave),
      contains('하루에 한 번밖에'),
    );
    expect(
      attendanceConfirmationMessage(AttendanceAction.checkOut),
      contains('17시 50분 이전'),
    );
  });

  test('remaining check-out time is calculated and formatted to seconds', () {
    final remaining = timeUntilConfirmationFreeCheckOut(
      DateTime(2026, 7, 16, 16, 47, 26),
    );

    expect(remaining, const Duration(hours: 1, minutes: 2, seconds: 34));
    expect(formatRemainingTime(remaining), '01시간 02분 34초');
    expect(
      timeUntilConfirmationFreeCheckOut(DateTime(2026, 7, 16, 17, 50)),
      Duration.zero,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:skala_attendance/features/attendance/presentation/attendance_display_formatter.dart';

void main() {
  test('formats the Korean date with its weekday', () {
    expect(formatAttendanceDate(DateTime(2026, 7, 24)), '7월 24일(금)');
  });

  test('formats ISO timestamps in Korea time without seconds', () {
    expect(formatAttendanceTime('2026-07-24T00:01:23Z'), '09:01');
    expect(formatAttendanceTime('2026-07-24T09:01:23+09:00'), '09:01');
  });

  test('normalizes plain times and preserves unexpected values', () {
    expect(formatAttendanceTime('09:01:23'), '09:01');
    expect(formatAttendanceTime('09:01'), '09:01');
    expect(formatAttendanceTime(null), '없음');
    expect(formatAttendanceTime('확인 중'), '확인 중');
  });

  test('preserves malformed or unsupported date and time values', () {
    expect(formatAttendanceTime('09:01:99'), '09:01:99');
    expect(formatAttendanceTime('2026-07-24'), '2026-07-24');
    expect(
      formatAttendanceTime('2026-07-24T00:01:99Z'),
      '2026-07-24T00:01:99Z',
    );
  });
}

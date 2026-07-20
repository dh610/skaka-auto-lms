import '../../schedule/domain/attendance_schedule.dart';

bool requiresAttendanceConfirmation(AttendanceAction action, {DateTime? now}) {
  if (action == AttendanceAction.leave) return true;
  if (action != AttendanceAction.checkOut) return false;

  final current = now ?? DateTime.now();
  return current.hour < 17 || (current.hour == 17 && current.minute < 50);
}

String attendanceConfirmationMessage(AttendanceAction action) {
  return switch (action) {
    AttendanceAction.leave => '외출은 하루에 한 번밖에 할 수 없습니다.\n정말 외출 처리하시겠습니까?',
    AttendanceAction.checkOut => '아직 오후 5시 50분 이전입니다.\n정말 퇴실 처리하시겠습니까?',
    _ => '${action.label} 기록을 전송하시겠습니까?',
  };
}

Duration timeUntilConfirmationFreeCheckOut(DateTime now) {
  final threshold = DateTime(now.year, now.month, now.day, 17, 50);
  if (!now.isBefore(threshold)) return Duration.zero;
  return threshold.difference(now);
}

String formatRemainingTime(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return '${hours.toString().padLeft(2, '0')}시간 '
      '${minutes.toString().padLeft(2, '0')}분 '
      '${seconds.toString().padLeft(2, '0')}초';
}

String formatRemainingClock(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

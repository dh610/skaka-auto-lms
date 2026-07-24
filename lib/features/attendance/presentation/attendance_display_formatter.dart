const _koreaOffset = Duration(hours: 9);
const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

String formatAttendanceDate(DateTime date) {
  final koreaDate = date.isUtc ? date.add(_koreaOffset) : date;
  final weekday = _weekdayLabels[koreaDate.weekday - 1];
  return '${koreaDate.month}월 ${koreaDate.day}일($weekday)';
}

String formatAttendanceTime(String? value) {
  if (value == null || value.trim().isEmpty) return '없음';
  final trimmed = value.trim();
  final plainTime = RegExp(
    r'^(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$',
  ).firstMatch(trimmed);
  if (plainTime != null) {
    final hour = int.parse(plainTime.group(1)!);
    final minute = int.parse(plainTime.group(2)!);
    if (hour < 24 && minute < 60) {
      return _formatClock(hour, minute);
    }
    return trimmed;
  }

  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) return trimmed;
  final koreaTime = parsed.isUtc ? parsed.add(_koreaOffset) : parsed;
  return _formatClock(koreaTime.hour, koreaTime.minute);
}

String _formatClock(int hour, int minute) {
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}

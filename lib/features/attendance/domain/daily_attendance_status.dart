import '../../schedule/domain/attendance_schedule.dart';
import 'attendance_snapshot.dart';

class DailyAttendanceStatus {
  const DailyAttendanceStatus.unqueried(this.koreaDate)
    : fetchedAt = null,
      checkInTime = null,
      checkOutTime = null,
      earlyLeaveTime = null,
      returnTime = null;

  const DailyAttendanceStatus.queried({
    required this.koreaDate,
    required this.fetchedAt,
    this.checkInTime,
    this.checkOutTime,
    this.earlyLeaveTime,
    this.returnTime,
  });

  factory DailyAttendanceStatus.fromSnapshot({
    required DateTime koreaDate,
    required DateTime fetchedAt,
    required AttendanceSnapshot snapshot,
  }) {
    return DailyAttendanceStatus.queried(
      koreaDate: koreaDate,
      fetchedAt: fetchedAt,
      checkInTime: snapshot.checkInTime,
      checkOutTime: snapshot.checkOutTime,
      earlyLeaveTime: snapshot.earlyLeaveTime,
      returnTime: snapshot.returnTime,
    );
  }

  final DateTime koreaDate;
  final DateTime? fetchedAt;
  final String? checkInTime;
  final String? checkOutTime;
  final String? earlyLeaveTime;
  final String? returnTime;

  bool get queried => fetchedAt != null;

  Set<AttendanceAction> get sequenceAvailableActions {
    if (checkOutTime != null) return const {};
    if (checkInTime == null) return const {AttendanceAction.checkIn};
    if (earlyLeaveTime != null && returnTime == null) {
      return const {AttendanceAction.returnFromLeave};
    }
    if (earlyLeaveTime != null) return const {AttendanceAction.checkOut};
    return const {AttendanceAction.leave, AttendanceAction.checkOut};
  }
}

import '../../schedule/domain/attendance_schedule.dart';

class AttendanceSnapshot {
  const AttendanceSnapshot({
    required this.networkAllowed,
    this.checkInTime,
    this.checkOutTime,
    this.earlyLeaveTime,
    this.returnTime,
  });

  factory AttendanceSnapshot.fromJson(Map<String, dynamic> json) {
    final attendance = json['attendance'] as Map<String, dynamic>? ?? const {};
    return AttendanceSnapshot(
      networkAllowed: json['networkAllowed'] == true,
      checkInTime: attendance['checkInTime'] as String?,
      checkOutTime: attendance['checkOutTime'] as String?,
      earlyLeaveTime: attendance['earlyLeaveTime'] as String?,
      returnTime: attendance['returnTime'] as String?,
    );
  }

  final bool networkAllowed;
  final String? checkInTime;
  final String? checkOutTime;
  final String? earlyLeaveTime;
  final String? returnTime;

  Set<AttendanceAction> get availableActions {
    if (!networkAllowed || checkOutTime != null) return const {};
    if (checkInTime == null) return const {AttendanceAction.checkIn};
    if (earlyLeaveTime != null && returnTime == null) {
      return const {AttendanceAction.returnFromLeave};
    }
    if (earlyLeaveTime != null) return const {AttendanceAction.checkOut};
    return const {AttendanceAction.leave, AttendanceAction.checkOut};
  }

  bool reflects(AttendanceAction action) {
    return switch (action) {
      AttendanceAction.checkIn => checkInTime != null,
      AttendanceAction.checkOut => checkOutTime != null,
      AttendanceAction.leave => earlyLeaveTime != null,
      AttendanceAction.returnFromLeave => returnTime != null,
    };
  }
}

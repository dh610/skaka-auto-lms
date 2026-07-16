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
}

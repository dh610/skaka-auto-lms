import '../../profile/domain/user_profile.dart';
import '../../schedule/domain/attendance_schedule.dart';
import '../domain/attendance_snapshot.dart';

class AttendanceActionRejectedException implements Exception {
  const AttendanceActionRejectedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AttendanceAuthenticationExpiredException implements Exception {
  const AttendanceAuthenticationExpiredException();
}

abstract interface class AttendanceGateway {
  Future<void> startBrowserAuthentication(UserProfile profile);

  void validateAttendanceToken(String token, UserProfile profile);

  Future<AttendanceSnapshot> fetchToday(String token);

  Future<void> recordAction(String token, AttendanceAction action);

  void close();
}

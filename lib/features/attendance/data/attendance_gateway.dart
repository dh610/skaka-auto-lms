import '../../profile/domain/user_profile.dart';
import '../domain/attendance_snapshot.dart';

abstract interface class AttendanceGateway {
  Future<void> startBrowserAuthentication(UserProfile profile);

  void validateAttendanceToken(String token, UserProfile profile);

  Future<AttendanceSnapshot> fetchToday(String token);

  void close();
}

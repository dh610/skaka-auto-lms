import 'package:flutter/material.dart';

import '../domain/attendance_schedule.dart';

extension AttendanceActionVisuals on AttendanceAction {
  IconData get icon => switch (this) {
    AttendanceAction.checkIn => Icons.login_rounded,
    AttendanceAction.checkOut => Icons.logout_rounded,
    AttendanceAction.leave => Icons.directions_walk_rounded,
    AttendanceAction.returnFromLeave => Icons.keyboard_return_rounded,
  };
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skala_attendance/features/attendance/data/skala_attendance_api.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';

void main() {
  test('record API sends bearer token and SKALA event type', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{}', 200);
    });
    final api = SkalaAttendanceApi(client: client);

    await api.recordAction('attendance-token', AttendanceAction.checkOut);

    expect(
      captured.url.toString(),
      'https://lms.skala-ai.com/api/trainee/attendance/today/record',
    );
    expect(captured.method, 'POST');
    expect(captured.headers['Authorization'], 'Bearer attendance-token');
    expect(jsonDecode(captured.body), {'eventType': 'CHECK_OUT'});
    api.close();
  });
}

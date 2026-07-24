import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skala_attendance/features/attendance/data/attendance_gateway.dart';
import 'package:skala_attendance/features/attendance/data/skala_attendance_api.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';
import 'package:skala_attendance/features/schedule/domain/attendance_schedule.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('iOS authentication opens an in-app Safari browser view', () async {
    late Uri openedUri;
    late LaunchMode openedMode;
    final client = MockClient(
      (_) async =>
          http.Response(jsonEncode({'preAuthToken': 'pre-token'}), 200),
    );
    final api = SkalaAttendanceApi(
      client: client,
      isAndroid: false,
      browserLauncher: (uri, mode) async {
        openedUri = uri;
        openedMode = mode;
        return true;
      },
    );

    await api.startBrowserAuthentication(
      const UserProfile(
        name: '윤동현',
        region: CampusRegion.pangyo5f,
        classNumber: 8,
      ),
    );

    expect(openedUri.host, 'lms.skala-ai.com');
    expect(openedUri.path, '/api/auth/att-verify-oauth-start');
    expect(openedUri.queryParameters['pat'], 'pre-token');
    expect(openedMode, LaunchMode.inAppBrowserView);
    api.close();
  });

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

  test('record API identifies a definitive server rejection', () async {
    final api = SkalaAttendanceApi(
      client: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'not allowed'}), 403),
      ),
    );

    await expectLater(
      api.recordAction('attendance-token', AttendanceAction.leave),
      throwsA(isA<AttendanceActionRejectedException>()),
    );
    api.close();
  });

  test(
    'status lookup retries once after a transient network failure',
    () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) throw const SocketException('network changed');
        return http.Response(jsonEncode({'networkAllowed': true}), 200);
      });
      final api = SkalaAttendanceApi(client: client);

      final snapshot = await api.fetchToday('attendance-token');

      expect(requestCount, 2);
      expect(snapshot.networkAllowed, isTrue);
      api.close();
    },
  );
}

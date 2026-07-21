import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skala_attendance/features/profile/data/skala_profile_verifier.dart';
import 'package:skala_attendance/features/profile/domain/profile_verifier.dart';
import 'package:skala_attendance/features/profile/domain/user_profile.dart';

void main() {
  const profile = UserProfile(
    name: '테스트 수강생',
    region: CampusRegion.pangyo5f,
    classNumber: 8,
  );

  test(
    'valid profile is accepted without exposing the pre-auth token',
    () async {
      late http.Request captured;
      final verifier = SkalaProfileVerifier(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'preAuthToken': 'discard-me'}), 200);
        }),
      );

      await verifier.verify(profile);

      expect(captured.method, 'POST');
      expect(jsonDecode(captured.body), {
        'traineeName': '테스트 수강생',
        'regionId': 'P2',
        'subGroupId': '8',
      });
      verifier.close();
    },
  );

  test('unknown profile becomes an invalid profile error', () async {
    final verifier = SkalaProfileVerifier(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'error': '이름이 일치하는 훈련생을 찾을 수 없습니다.'})),
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    expect(verifier.verify(profile), throwsA(isA<InvalidProfileException>()));
    verifier.close();
  });

  test('server failures are not reported as invalid profile data', () async {
    final verifier = SkalaProfileVerifier(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );

    expect(
      verifier.verify(profile),
      throwsA(isA<ProfileVerificationUnavailableException>()),
    );
    verifier.close();
  });
}

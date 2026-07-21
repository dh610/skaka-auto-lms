import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../domain/profile_verifier.dart';
import '../domain/user_profile.dart';

class SkalaProfileVerifier implements ProfileVerifier {
  static final Uri _preVerifyUri = Uri.parse(
    'https://lms.skala-ai.com/api/public/attendance/pre-verify',
  );

  SkalaProfileVerifier({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<void> verify(UserProfile profile) async {
    try {
      final response = await _client
          .post(
            _preVerifyUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'traineeName': profile.name,
              'regionId': profile.region.id,
              'subGroupId': profile.subGroupId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = _decodeBody(response);
        final token = body?['preAuthToken'] as String?;
        if (token == null || token.isEmpty) {
          throw const ProfileVerificationUnavailableException();
        }
        return;
      }

      final error = _decodeBody(response)?['error']?.toString() ?? '';
      if (response.statusCode == 401 &&
          (error.contains('훈련생') || error.contains('이름'))) {
        throw const InvalidProfileException();
      }
      throw const ProfileVerificationUnavailableException();
    } on ProfileVerificationException {
      rethrow;
    } on SocketException catch (_) {
      throw const ProfileVerificationUnavailableException();
    } on TimeoutException catch (_) {
      throw const ProfileVerificationUnavailableException();
    } on http.ClientException catch (_) {
      throw const ProfileVerificationUnavailableException();
    } on FormatException catch (_) {
      throw const ProfileVerificationUnavailableException();
    }
  }

  Map<String, dynamic>? _decodeBody(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  @override
  void close() => _client.close();
}

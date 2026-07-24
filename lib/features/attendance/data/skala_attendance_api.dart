import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../profile/domain/user_profile.dart';
import '../../schedule/domain/attendance_schedule.dart';
import '../domain/attendance_snapshot.dart';
import 'attendance_gateway.dart';

typedef BrowserLauncher = Future<bool> Function(Uri uri, LaunchMode mode);

class SkalaAttendanceApi implements AttendanceGateway {
  static const _browserChannel = MethodChannel('skala_attendance/browser');
  static final Uri _preVerifyUri = Uri.parse(
    'https://lms.skala-ai.com/api/public/attendance/pre-verify',
  );
  static final Uri _todayUri = Uri.parse(
    'https://lms.skala-ai.com/api/trainee/attendance/today',
  );
  static final Uri _recordUri = Uri.parse(
    'https://lms.skala-ai.com/api/trainee/attendance/today/record',
  );

  SkalaAttendanceApi({
    http.Client? client,
    BrowserLauncher? browserLauncher,
    bool? isAndroid,
  }) : _browserLauncher = browserLauncher ?? _launchBrowser,
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  http.Client _client;
  final bool _ownsClient;
  final BrowserLauncher _browserLauncher;
  final bool _isAndroid;

  static Future<bool> _launchBrowser(Uri uri, LaunchMode mode) =>
      launchUrl(uri, mode: mode);

  @override
  Future<void> startBrowserAuthentication(UserProfile profile) async {
    // A rejected pre-verification request can leave a keep-alive connection
    // bound to the previous mobile or VPN network. Always start authentication
    // with a fresh client so a newly connected SKALA Wi-Fi is used immediately.
    _resetOwnedClient();
    final response = await _requestWithReconnect(
      () => _client
          .post(
            _preVerifyUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'traineeName': profile.name,
              'regionId': profile.region.id,
              'subGroupId': profile.subGroupId,
            }),
          )
          .timeout(const Duration(seconds: 10)),
    );
    if (response.statusCode != 200) {
      throw StateError(_serverError(response));
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final preAuthToken = body['preAuthToken'] as String?;
    if (preAuthToken == null || preAuthToken.isEmpty) {
      throw StateError('사전 인증 토큰이 없습니다.');
    }
    final oauthStart = Uri.https(
      'lms.skala-ai.com',
      '/api/auth/att-verify-oauth-start',
      {'pat': preAuthToken},
    );
    if (_isAndroid) {
      await _browserChannel.invokeMethod<bool>('openCustomTab', {
        'url': oauthStart.toString(),
      });
    } else {
      final opened = await _browserLauncher(
        oauthStart,
        LaunchMode.inAppBrowserView,
      );
      if (!opened) throw StateError('앱 내 브라우저를 열 수 없습니다.');
    }
  }

  @override
  void validateAttendanceToken(String token, UserProfile profile) {
    final parts = token.split('.');
    if (parts.length != 3) throw const FormatException('JWT 형식이 아닙니다.');
    final payload =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, dynamic>;
    final expiration = payload['exp'] as num?;
    if (expiration == null ||
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 >=
            expiration.toInt()) {
      throw const FormatException('토큰이 만료됐습니다.');
    }
    final koreaNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final koreaDate =
        '${koreaNow.year.toString().padLeft(4, '0')}-'
        '${koreaNow.month.toString().padLeft(2, '0')}-'
        '${koreaNow.day.toString().padLeft(2, '0')}';
    if (payload['date'] != koreaDate ||
        payload['regionId'] != profile.region.id ||
        payload['subGroupId'].toString() != profile.subGroupId) {
      throw const FormatException('현재 사용자 설정과 맞지 않는 토큰입니다.');
    }
  }

  @override
  Future<AttendanceSnapshot> fetchToday(String token) async {
    final response = await _requestWithReconnect(
      () => _client
          .get(
            _todayUri.replace(
              queryParameters: {
                '_t': '${DateTime.now().millisecondsSinceEpoch}',
              },
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Cache-Control': 'no-cache, no-store',
            },
          )
          .timeout(const Duration(seconds: 10)),
    );
    if (response.statusCode != 200) throw StateError(_serverError(response));
    return AttendanceSnapshot.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> recordAction(String token, AttendanceAction action) async {
    final response = await _client
        .post(
          _recordUri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'eventType': action.eventType}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _serverError(response);
      if (_isDefinitiveActionRejection(response.statusCode)) {
        throw AttendanceActionRejectedException(error);
      }
      throw StateError(error);
    }
  }

  bool _isDefinitiveActionRejection(int statusCode) {
    if (statusCode < 400 || statusCode >= 500) return false;
    return statusCode != 408 &&
        statusCode != 409 &&
        statusCode != 425 &&
        statusCode != 429;
  }

  String _serverError(http.Response response) {
    try {
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return body['error']?.toString() ?? 'HTTP ${response.statusCode}';
    } catch (_) {
      return 'HTTP ${response.statusCode}';
    }
  }

  Future<http.Response> _requestWithReconnect(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request();
    } catch (error) {
      if (!_isTransientNetworkError(error)) rethrow;
      _resetOwnedClient();
      return request();
    }
  }

  bool _isTransientNetworkError(Object error) {
    return error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException;
  }

  void _resetOwnedClient() {
    if (!_ownsClient) return;
    _client.close();
    _client = http.Client();
  }

  @override
  void close() => _client.close();
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../profile/domain/user_profile.dart';
import '../../schedule/domain/attendance_schedule.dart';
import '../data/attendance_gateway.dart';
import '../domain/attendance_snapshot.dart';

class AttendanceController extends ChangeNotifier {
  AttendanceController(this._profile, this._gateway, {bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid;

  UserProfile _profile;
  final AttendanceGateway _gateway;
  final bool _isAndroid;

  bool _busy = false;
  String _message = 'Google 인증 후 출결 정보를 확인하세요.';
  AttendanceSnapshot? _snapshot;
  String? _token;
  _AttendanceRecovery? _recovery;
  bool _hasError = false;

  bool get busy => _busy;
  String get message => _message;
  AttendanceSnapshot? get snapshot => _snapshot;
  bool get authenticated => _token != null;
  bool get hasError => _hasError;
  bool get canRetry => _recovery != null;
  String get retryLabel => switch (_recovery) {
    _AttendanceRecovery.refresh => '출결 상태 다시 조회',
    _ => 'Google 인증 다시 시도',
  };

  void updateProfile(UserProfile profile) {
    _profile = profile;
    _token = null;
    _setState(
      clearSnapshot: true,
      message: '사용자 정보가 변경되었습니다. 다시 인증해주세요.',
      recovery: _AttendanceRecovery.authenticate,
    );
  }

  Future<void> startAuthentication() async {
    _token = null;
    _setState(
      busy: true,
      clearSnapshot: true,
      message: '본인 확인 중…',
      clearRecovery: true,
    );
    try {
      await _gateway.startBrowserAuthentication(_profile);
      _setState(
        message: _isAndroid
            ? 'Chrome에서 Google 계정을 선택하세요. 인증 후 앱으로 돌아옵니다.'
            : 'Safari에서 Google 계정을 선택한 뒤 SKALA 웹 화면에서 원하는 동작을 수행하세요.',
      );
    } catch (error) {
      _setState(
        message: _friendlyError(error, operation: 'Google 인증을 시작하지 못했습니다.'),
        hasError: true,
        recovery: _AttendanceRecovery.authenticate,
      );
    } finally {
      _setState(busy: false);
    }
  }

  Future<void> handleCallback(Uri uri) async {
    if (!_isAndroid ||
        uri.scheme != 'https' ||
        uri.host != 'att.skala-ai.com') {
      return;
    }
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) {
      _setState(
        message: '인증 정보가 전달되지 않았습니다. Google 인증을 다시 진행해주세요.',
        hasError: true,
        recovery: _AttendanceRecovery.authenticate,
      );
      return;
    }
    _setState(busy: true, message: '인증 토큰 확인 및 상태 조회 중…');
    try {
      _gateway.validateAttendanceToken(token, _profile);
      final snapshot = await _gateway.fetchToday(token);
      _token = token;
      _setState(
        snapshot: snapshot,
        message: '인증 및 상태 조회에 성공했습니다.',
        clearRecovery: true,
      );
    } catch (error) {
      _token = null;
      _setState(
        message: _friendlyError(error, operation: '출결 정보를 불러오지 못했습니다.'),
        hasError: true,
        recovery: _AttendanceRecovery.authenticate,
      );
    } finally {
      _setState(busy: false);
    }
  }

  Future<void> performAction(AttendanceAction action) async {
    final token = _token;
    final current = _snapshot;
    if (token == null || current == null) {
      _setState(message: 'Google 인증이 필요합니다.');
      return;
    }
    if (!current.availableActions.contains(action)) {
      _setState(message: '현재 출결 상태에서는 ${action.label}할 수 없습니다.');
      return;
    }
    _setState(busy: true, message: '${action.label} 요청 전송 중…');
    try {
      await _gateway.recordAction(token, action);
      final updated = await _gateway.fetchToday(token);
      if (!updated.reflects(action)) {
        throw StateError('서버 상태에서 ${action.label} 반영을 확인하지 못했습니다.');
      }
      _setState(snapshot: updated, message: '${action.label} 처리가 완료되었습니다.');
    } catch (error) {
      _setState(
        message: _friendlyError(
          error,
          operation: '${action.label} 처리 결과를 확인하지 못했습니다.',
          suffix: '중복 전송하지 말고 먼저 현재 출결 상태를 다시 확인해주세요.',
        ),
        hasError: true,
        recovery: _AttendanceRecovery.refresh,
      );
    } finally {
      _setState(busy: false);
    }
  }

  void reportUnavailableScheduledAction(AttendanceAction action) {
    _setState(message: '예약된 ${action.label} 동작은 현재 출결 상태에서 실행할 수 없습니다.');
  }

  void reportLinkError(Object error) {
    _setState(
      message: '인증 결과를 앱으로 가져오지 못했습니다. Google 인증을 다시 진행해주세요.',
      hasError: true,
      recovery: _AttendanceRecovery.authenticate,
    );
  }

  Future<void> retry() async {
    switch (_recovery) {
      case _AttendanceRecovery.authenticate:
        await startAuthentication();
      case _AttendanceRecovery.refresh:
        await refreshStatus();
      case null:
        return;
    }
  }

  Future<void> refreshStatus() async {
    final token = _token;
    if (token == null) {
      await startAuthentication();
      return;
    }
    _setState(busy: true, message: '현재 출결 상태 확인 중…', clearRecovery: true);
    try {
      final snapshot = await _gateway.fetchToday(token);
      _setState(
        snapshot: snapshot,
        message: '현재 출결 상태를 다시 확인했습니다.',
        clearRecovery: true,
      );
    } catch (error) {
      _setState(
        message: _friendlyError(error, operation: '출결 정보를 불러오지 못했습니다.'),
        hasError: true,
        recovery: _AttendanceRecovery.refresh,
      );
    } finally {
      _setState(busy: false);
    }
  }

  void _setState({
    bool? busy,
    String? message,
    AttendanceSnapshot? snapshot,
    bool clearSnapshot = false,
    bool? hasError,
    _AttendanceRecovery? recovery,
    bool clearRecovery = false,
  }) {
    if (busy != null) _busy = busy;
    if (message != null) _message = message;
    if (clearSnapshot) _snapshot = null;
    if (snapshot != null) _snapshot = snapshot;
    if (hasError != null) _hasError = hasError;
    if (clearRecovery) {
      _recovery = null;
      _hasError = false;
    } else if (recovery != null) {
      _recovery = recovery;
    }
    notifyListeners();
  }

  String _friendlyError(
    Object error, {
    required String operation,
    String? suffix,
  }) {
    final guidance = switch (error) {
      TimeoutException() => '응답 시간이 초과되었습니다. 인터넷 연결을 확인해주세요.',
      SocketException() => '인터넷에 연결할 수 없습니다. 네트워크 상태를 확인해주세요.',
      FormatException() => '인증 정보가 올바르지 않거나 만료되었습니다.',
      StateError() => 'SKALA 서버가 요청을 처리하지 못했습니다. 잠시 후 다시 시도해주세요.',
      _ => '예상하지 못한 오류가 발생했습니다. 잠시 후 다시 시도해주세요.',
    };
    return [operation, guidance, ?suffix].join(' ');
  }

  @override
  void dispose() {
    _gateway.close();
    super.dispose();
  }
}

enum _AttendanceRecovery { authenticate, refresh }

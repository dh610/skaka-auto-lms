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
  String _message = '아직 인증하지 않았습니다.';
  AttendanceSnapshot? _snapshot;
  String? _token;

  bool get busy => _busy;
  String get message => _message;
  AttendanceSnapshot? get snapshot => _snapshot;
  bool get authenticated => _token != null;
  String get platformDescription =>
      _isAndroid ? 'Android · 인증 후 앱에서 상태 조회' : 'iOS · 인증 후 Safari에서 수동 처리';

  void updateProfile(UserProfile profile) {
    _profile = profile;
    _token = null;
    _setState(clearSnapshot: true, message: '사용자 정보가 변경되었습니다. 다시 인증해주세요.');
  }

  Future<void> startAuthentication() async {
    _token = null;
    _setState(busy: true, clearSnapshot: true, message: '본인 확인 중…');
    try {
      await _gateway.startBrowserAuthentication(_profile);
      _setState(
        message: _isAndroid
            ? 'Chrome에서 Google 계정을 선택하세요. 인증 후 앱으로 돌아옵니다.'
            : 'Safari에서 Google 계정을 선택한 뒤 SKALA 웹 화면에서 원하는 동작을 수행하세요.',
      );
    } catch (error) {
      _setState(message: '인증 시작 실패: $error');
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
      _setState(message: '인증 콜백에 토큰이 없습니다.');
      return;
    }
    _setState(busy: true, message: '인증 토큰 확인 및 상태 조회 중…');
    try {
      _gateway.validateAttendanceToken(token, _profile);
      final snapshot = await _gateway.fetchToday(token);
      _token = token;
      _setState(snapshot: snapshot, message: '인증 및 상태 조회에 성공했습니다.');
    } catch (error) {
      _setState(message: '콜백 처리 실패: $error');
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
      _setState(message: '${action.label} 처리 실패: $error');
    } finally {
      _setState(busy: false);
    }
  }

  void reportUnavailableScheduledAction(AttendanceAction action) {
    _setState(message: '예약된 ${action.label} 동작은 현재 출결 상태에서 실행할 수 없습니다.');
  }

  void reportLinkError(Object error) {
    _setState(message: '앱 링크 오류: $error');
  }

  void _setState({
    bool? busy,
    String? message,
    AttendanceSnapshot? snapshot,
    bool clearSnapshot = false,
  }) {
    if (busy != null) _busy = busy;
    if (message != null) _message = message;
    if (clearSnapshot) _snapshot = null;
    if (snapshot != null) _snapshot = snapshot;
    notifyListeners();
  }

  @override
  void dispose() {
    _gateway.close();
    super.dispose();
  }
}

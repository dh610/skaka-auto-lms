import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../profile/domain/user_profile.dart';
import '../../schedule/domain/attendance_schedule.dart';
import '../data/attendance_completion_store.dart';
import '../data/attendance_gateway.dart';
import '../data/attendance_status_store.dart';
import '../domain/attendance_snapshot.dart';
import '../domain/daily_attendance_status.dart';

enum AttendanceRequestResult { completed, authenticationRequired }

class AttendanceController extends ChangeNotifier {
  AttendanceController(
    this._profile,
    this._gateway, {
    bool? isAndroid,
    this.completionStore,
    this.statusStore,
    DateTime Function()? now,
  }) : _isAndroid = isAndroid ?? Platform.isAndroid,
       _now = now ?? DateTime.now {
    _dailyStatus = DailyAttendanceStatus.unqueried(_koreaDate(_now()));
  }

  UserProfile _profile;
  final AttendanceGateway _gateway;
  final bool _isAndroid;
  final DateTime Function() _now;
  final AttendanceCompletionStore? completionStore;
  final AttendanceStatusStore? statusStore;

  bool _busy = false;
  String _message = 'Google 인증 후 출결 정보를 확인하세요.';
  AttendanceSnapshot? _snapshot;
  String? _token;
  _AttendanceRecovery? _recovery;
  bool _hasError = false;
  int _statusRevision = 0;
  int _completionRevision = 0;
  AttendanceAction? _lastCompletedAction;
  AttendanceAction? _pendingActionConfirmation;
  _AttendanceRequest? _pendingRequest;
  AttendanceAction? _readyAction;
  int _readyActionRevision = 0;
  bool _awaitingAuthenticationCallback = false;
  DateTime? _snapshotKoreaDate;
  late DailyAttendanceStatus _dailyStatus;
  int _sessionRevision = 0;
  Future<void> _statusStoreOperation = Future.value();
  Map<String, DateTime> _completedOccurrences = {};
  Map<String, DateTime> _skippedOccurrences = {};

  bool get busy => _busy;
  String get message => _message;
  AttendanceSnapshot? get snapshot => _snapshot;
  DailyAttendanceStatus get dailyStatus => _dailyStatus;
  bool get authenticated => _token != null;
  bool get hasError => _hasError;
  int get statusRevision => _statusRevision;
  int get completionRevision => _completionRevision;
  AttendanceAction? get lastCompletedAction => _lastCompletedAction;
  AttendanceAction? get readyAction => _readyAction;
  int get readyActionRevision => _readyActionRevision;
  bool get awaitingAuthenticationCallback => _awaitingAuthenticationCallback;
  bool get canRetry => _recovery != null;
  bool get retryRequiresAuthentication =>
      _recovery == _AttendanceRecovery.authenticate;
  String get retryLabel => switch (_recovery) {
    _AttendanceRecovery.refresh => '출결 상태 다시 조회',
    _ => 'Google 인증 다시 시도',
  };

  Future<void> loadDailyStatus() async {
    final store = statusStore;
    if (store == null) return;
    final sessionRevision = _sessionRevision;
    final statusRevision = _statusRevision;
    final koreaDate = _koreaDate(_now());
    final restored = await store.loadFor(koreaDate);
    if (!_operationIsCurrent(sessionRevision, koreaDate) ||
        statusRevision != _statusRevision ||
        restored.koreaDate != koreaDate) {
      return;
    }
    _dailyStatus = restored;
    notifyListeners();
  }

  bool wasScheduleCompleted(AttendanceSchedule schedule, DateTime date) {
    return _occurrenceWasRecorded(_completedOccurrences, schedule, date);
  }

  bool wasScheduleSkipped(AttendanceSchedule schedule, DateTime date) {
    return _occurrenceWasRecorded(_skippedOccurrences, schedule, date);
  }

  bool _occurrenceWasRecorded(
    Map<String, DateTime> occurrences,
    AttendanceSchedule schedule,
    DateTime date,
  ) {
    final scheduledAt = DateTime(
      date.year,
      date.month,
      date.day,
      schedule.hour,
      schedule.minute,
    );
    return occurrences.containsKey(
      AttendanceCompletionStore.occurrenceKey(schedule.id, scheduledAt),
    );
  }

  Future<void> loadCompletionHistory({DateTime? now}) async {
    final store = completionStore;
    if (store == null) return;
    final targetDate = now ?? DateTime.now();
    _completedOccurrences = await store.loadFor(targetDate);
    _skippedOccurrences = await store.loadSkippedFor(targetDate);
    notifyListeners();
  }

  Future<void> setScheduleSkipped(
    AttendanceSchedule schedule,
    DateTime date, {
    required bool skipped,
  }) async {
    final scheduledAt = DateTime(
      date.year,
      date.month,
      date.day,
      schedule.hour,
      schedule.minute,
    );
    final key = AttendanceCompletionStore.occurrenceKey(
      schedule.id,
      scheduledAt,
    );
    if (skipped) {
      _skippedOccurrences[key] = DateTime.now();
    } else {
      _skippedOccurrences.remove(key);
    }
    await completionStore?.saveSkipped(_skippedOccurrences);
    notifyListeners();
  }

  void updateProfile(UserProfile profile) {
    _sessionRevision++;
    _profile = profile;
    _token = null;
    _lastCompletedAction = null;
    _pendingActionConfirmation = null;
    _pendingRequest = null;
    _readyAction = null;
    _awaitingAuthenticationCallback = false;
    _snapshotKoreaDate = null;
    _dailyStatus = DailyAttendanceStatus.unqueried(_koreaDate(_now()));
    _completedOccurrences = {};
    _skippedOccurrences = {};
    if (completionStore case final store?) unawaited(store.clear());
    _clearDailyStatusStore();
    _setState(
      busy: false,
      clearSnapshot: true,
      message: '사용자 정보가 변경되었습니다. 다시 인증해주세요.',
      recovery: _AttendanceRecovery.authenticate,
    );
  }

  Future<void> startAuthentication({
    String? scheduleId,
    DateTime? scheduledAt,
  }) async {
    invalidateExpiredDailyState();
    if (_awaitingAuthenticationCallback) return;
    _pendingRequest ??= const _StatusRefreshRequest();
    final sessionRevision = ++_sessionRevision;
    final operationDate = _koreaDate(_now());
    _token = null;
    _lastCompletedAction = null;
    _pendingActionConfirmation = null;
    _readyAction = null;
    _snapshotKoreaDate = null;
    _setState(
      busy: true,
      clearSnapshot: true,
      message: '본인 확인 중…',
      clearRecovery: true,
    );
    try {
      await _gateway.startBrowserAuthentication(_profile);
      if (!_operationIsCurrent(sessionRevision, operationDate)) return;
      if (scheduleId != null && scheduledAt != null) {
        await _rememberScheduledOccurrence(scheduleId, scheduledAt);
        if (!_operationIsCurrent(sessionRevision, operationDate)) return;
      }
      _awaitingAuthenticationCallback = _isAndroid;
      _setState(
        message: _isAndroid
            ? 'Chrome에서 Google 계정을 선택하세요. 인증 후 앱으로 돌아옵니다.'
            : '앱 내 Safari 화면에서 Google 계정을 선택한 뒤 SKALA 웹 화면에서 원하는 동작을 수행하세요.',
      );
    } catch (error) {
      if (!_operationIsCurrent(sessionRevision, operationDate)) return;
      _awaitingAuthenticationCallback = false;
      _setState(
        message: _friendlyError(error, operation: 'Google 인증을 시작하지 못했습니다.'),
        hasError: true,
        recovery: _AttendanceRecovery.authenticate,
      );
    } finally {
      if (sessionRevision == _sessionRevision) _setState(busy: false);
    }
  }

  Future<AttendanceRequestResult> requestStatusRefresh() {
    return _request(const _StatusRefreshRequest());
  }

  Future<AttendanceRequestResult> requestAction(
    AttendanceAction action, {
    String? scheduleId,
    DateTime? scheduledAt,
  }) {
    return _request(
      _ActionRequest(action),
      scheduleId: scheduleId,
      scheduledAt: scheduledAt,
    );
  }

  void cancelPendingRequest() {
    if (_pendingRequest == null && !_awaitingAuthenticationCallback) return;
    _sessionRevision++;
    _pendingRequest = null;
    _awaitingAuthenticationCallback = false;
    _setState(busy: false);
  }

  void cancelReadyAction() {
    _readyAction = null;
    notifyListeners();
  }

  Future<AttendanceRequestResult> _request(
    _AttendanceRequest request, {
    String? scheduleId,
    DateTime? scheduledAt,
  }) async {
    invalidateExpiredDailyState();
    if (_awaitingAuthenticationCallback) {
      return AttendanceRequestResult.completed;
    }
    final sessionRevision = ++_sessionRevision;
    final operationDate = _koreaDate(_now());
    _pendingRequest = request;
    _readyAction = null;

    if (scheduleId != null && scheduledAt != null) {
      await _rememberScheduledOccurrence(scheduleId, scheduledAt);
      if (!_operationIsCurrent(sessionRevision, operationDate)) {
        return AttendanceRequestResult.completed;
      }
    }

    final token = _token;
    if (token == null) {
      _setAuthenticationRequiredState();
      return AttendanceRequestResult.authenticationRequired;
    }

    try {
      _gateway.validateAttendanceToken(token, _profile);
    } catch (_) {
      if (!_operationIsCurrent(sessionRevision, operationDate, token: token)) {
        return AttendanceRequestResult.completed;
      }
      _token = null;
      _setAuthenticationRequiredState();
      return AttendanceRequestResult.authenticationRequired;
    }

    _setState(busy: true, message: '현재 출결 상태 확인 중…', clearRecovery: true);
    try {
      final snapshot = await _gateway.fetchToday(token);
      if (!_operationIsCurrent(sessionRevision, operationDate, token: token)) {
        return AttendanceRequestResult.completed;
      }
      await _publishRequestedSnapshot(
        snapshot,
        request: request,
        koreaDate: operationDate,
        refreshMessage: '현재 출결 상태를 다시 확인했습니다.',
      );
      return AttendanceRequestResult.completed;
    } on AttendanceAuthenticationExpiredException {
      if (!_operationIsCurrent(sessionRevision, operationDate, token: token)) {
        return AttendanceRequestResult.completed;
      }
      _token = null;
      _setAuthenticationRequiredState();
      return AttendanceRequestResult.authenticationRequired;
    } catch (error) {
      if (!_operationIsCurrent(sessionRevision, operationDate, token: token)) {
        return AttendanceRequestResult.completed;
      }
      _pendingRequest = null;
      _setState(
        message: _friendlyError(error, operation: '출결 정보를 불러오지 못했습니다.'),
        hasError: true,
        recovery: _AttendanceRecovery.refresh,
      );
      return AttendanceRequestResult.completed;
    } finally {
      if (sessionRevision == _sessionRevision) _setState(busy: false);
    }
  }

  void _setAuthenticationRequiredState() {
    _setState(
      busy: false,
      message: 'Google 인증이 필요합니다.',
      hasError: false,
      recovery: _AttendanceRecovery.authenticate,
    );
  }

  Future<void> handleCallback(Uri uri) async {
    if (!_isAndroid ||
        uri.scheme != 'https' ||
        uri.host != 'att.skala-ai.com') {
      return;
    }
    _awaitingAuthenticationCallback = false;
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) {
      _sessionRevision++;
      _setState(
        busy: false,
        message: '인증 정보가 전달되지 않았습니다. Google 인증을 다시 진행해주세요.',
        hasError: true,
        recovery: _AttendanceRecovery.authenticate,
      );
      return;
    }
    invalidateExpiredDailyState();
    _pendingRequest ??= const _StatusRefreshRequest();
    final sessionRevision = ++_sessionRevision;
    final operationDate = _koreaDate(_now());
    _token = null;
    _lastCompletedAction = null;
    _pendingActionConfirmation = null;
    _readyAction = null;
    _snapshotKoreaDate = null;
    _setState(busy: true, clearSnapshot: true, message: '인증 토큰 확인 및 상태 조회 중…');
    try {
      _gateway.validateAttendanceToken(token, _profile);
      final snapshot = await _gateway.fetchToday(token);
      if (!_operationIsCurrent(sessionRevision, operationDate)) return;
      _token = token;
      await _publishRequestedSnapshot(
        snapshot,
        request: _pendingRequest ?? const _StatusRefreshRequest(),
        koreaDate: operationDate,
        refreshMessage: '인증 및 상태 조회에 성공했습니다.',
      );
    } on AttendanceAuthenticationExpiredException catch (error) {
      if (!_operationIsCurrent(sessionRevision, operationDate)) return;
      _token = null;
      _setState(
        message: _friendlyError(error, operation: '출결 정보를 불러오지 못했습니다.'),
        hasError: true,
        recovery: _AttendanceRecovery.authenticate,
      );
    } catch (error) {
      if (!_operationIsCurrent(sessionRevision, operationDate)) return;
      _token = null;
      _setState(
        message: _friendlyError(error, operation: '출결 정보를 불러오지 못했습니다.'),
        hasError: true,
        recovery: _AttendanceRecovery.authenticate,
      );
    } finally {
      if (sessionRevision == _sessionRevision) _setState(busy: false);
    }
  }

  Future<void> performAction(
    AttendanceAction action, {
    int? readyActionRevision,
  }) async {
    if (invalidateExpiredDailyState()) return;
    if (_readyAction != action ||
        readyActionRevision == null ||
        readyActionRevision != _readyActionRevision) {
      _setState(message: '출결 상태가 변경되었습니다. 최신 상태를 다시 확인해주세요.');
      return;
    }
    _readyAction = null;
    notifyListeners();
    final sessionRevision = _sessionRevision;
    final operationDate = _koreaDate(_now());
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
    _pendingActionConfirmation = action;
    try {
      await _gateway.recordAction(token, action);
      if (!_operationIsCurrent(sessionRevision, operationDate, token: token)) {
        return;
      }
      final updated = await _gateway.fetchToday(token);
      if (!_operationIsCurrent(sessionRevision, operationDate, token: token)) {
        return;
      }
      if (!updated.reflects(action)) {
        throw StateError('서버 상태에서 ${action.label} 반영을 확인하지 못했습니다.');
      }
      await _publishSnapshot(
        updated,
        message: '${action.label} 처리가 완료되었습니다.',
        completedAction: action,
        koreaDate: operationDate,
      );
    } catch (error) {
      if (!_operationIsCurrent(sessionRevision, operationDate, token: token)) {
        return;
      }
      final definitelyRejected = error is AttendanceActionRejectedException;
      if (definitelyRejected) _pendingActionConfirmation = null;
      _setState(
        message: definitelyRejected
            ? '${action.label} 요청이 서버에서 거부되었습니다. '
                  '현재 출결 상태를 다시 확인해주세요.'
            : _friendlyError(
                error,
                operation: '${action.label} 처리 결과를 확인하지 못했습니다.',
                suffix: '중복 전송하지 말고 먼저 현재 출결 상태를 다시 확인해주세요.',
              ),
        hasError: true,
        recovery: _AttendanceRecovery.refresh,
      );
    } finally {
      if (sessionRevision == _sessionRevision) _setState(busy: false);
    }
  }

  void reportUnavailableScheduledAction(AttendanceAction action) {
    _setState(message: '예약된 ${action.label} 동작은 현재 출결 상태에서 실행할 수 없습니다.');
  }

  void reportStaleScheduledOccurrence() {
    _setState(message: '변경되거나 삭제된 일정의 알림이라 실행하지 않았습니다.');
  }

  void reportLinkError(Object error) {
    _sessionRevision++;
    _awaitingAuthenticationCallback = false;
    _setState(
      busy: false,
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
    if (invalidateExpiredDailyState()) return;
    final sessionRevision = _sessionRevision;
    final operationDate = _koreaDate(_now());
    final token = _token;
    if (token == null) {
      await startAuthentication();
      return;
    }
    _setState(busy: true, message: '현재 출결 상태 확인 중…', clearRecovery: true);
    try {
      final snapshot = await _gateway.fetchToday(token);
      if (!_operationIsCurrent(sessionRevision, operationDate, token: token)) {
        return;
      }
      final pendingAction = _pendingActionConfirmation;
      if (pendingAction != null && !snapshot.reflects(pendingAction)) {
        throw StateError('서버 상태에서 ${pendingAction.label} 반영을 확인하지 못했습니다.');
      }
      await _publishSnapshot(
        snapshot,
        message: pendingAction == null
            ? '현재 출결 상태를 다시 확인했습니다.'
            : '${pendingAction.label} 처리가 완료되었습니다.',
        completedAction: pendingAction,
        koreaDate: operationDate,
      );
    } catch (error) {
      if (!_operationIsCurrent(sessionRevision, operationDate, token: token)) {
        return;
      }
      _setState(
        message: _friendlyError(error, operation: '출결 정보를 불러오지 못했습니다.'),
        hasError: true,
        recovery: _AttendanceRecovery.refresh,
      );
    } finally {
      if (sessionRevision == _sessionRevision) _setState(busy: false);
    }
  }

  Future<void> _publishSnapshot(
    AttendanceSnapshot snapshot, {
    required String message,
    AttendanceAction? completedAction,
    DateTime? koreaDate,
  }) async {
    final snapshotDate = koreaDate ?? _koreaDate(_now());
    _snapshotKoreaDate = snapshotDate;
    _dailyStatus = DailyAttendanceStatus.fromSnapshot(
      koreaDate: snapshotDate,
      fetchedAt: _now(),
      snapshot: snapshot,
    );
    _statusRevision++;
    if (completedAction != null) {
      _completionRevision++;
      _lastCompletedAction = completedAction;
      _pendingActionConfirmation = null;
    }
    _setState(snapshot: snapshot, message: message, clearRecovery: true);
    await _saveDailyStatus(_dailyStatus);
  }

  Future<void> _publishRequestedSnapshot(
    AttendanceSnapshot snapshot, {
    required _AttendanceRequest request,
    required DateTime koreaDate,
    required String refreshMessage,
  }) async {
    _pendingRequest = null;
    switch (request) {
      case _StatusRefreshRequest():
        await _publishSnapshot(
          snapshot,
          message: refreshMessage,
          koreaDate: koreaDate,
        );
      case _ActionRequest(:final action):
        final available = snapshot.availableActions.contains(action);
        if (available) {
          _readyAction = action;
          _readyActionRevision++;
        }
        await _publishSnapshot(
          snapshot,
          message: available
              ? '최신 출결 상태를 확인했습니다. ${action.label} 동작을 확인해주세요.'
              : '현재 출결 상태에서는 ${action.label}할 수 없습니다.',
          koreaDate: koreaDate,
        );
    }
  }

  bool invalidateExpiredDailyState() {
    final snapshotDate = _snapshotKoreaDate;
    final koreaDate = _koreaDate(_now());
    if ((snapshotDate == null || snapshotDate == koreaDate) &&
        _dailyStatus.koreaDate == koreaDate) {
      return false;
    }
    _expireDailySession();
    return true;
  }

  bool _operationIsCurrent(
    int sessionRevision,
    DateTime operationDate, {
    String? token,
  }) {
    if (sessionRevision != _sessionRevision) return false;
    if (operationDate != _koreaDate(_now())) {
      _expireDailySession();
      return false;
    }
    return token == null || token == _token;
  }

  void _expireDailySession() {
    _sessionRevision++;
    _token = null;
    _snapshotKoreaDate = null;
    _dailyStatus = DailyAttendanceStatus.unqueried(_koreaDate(_now()));
    _lastCompletedAction = null;
    _pendingActionConfirmation = null;
    _pendingRequest = null;
    _readyAction = null;
    _awaitingAuthenticationCallback = false;
    _setState(
      busy: false,
      clearSnapshot: true,
      message: '날짜가 바뀌어 오늘 출결 정보를 다시 확인해야 합니다.',
      recovery: _AttendanceRecovery.authenticate,
    );
    _clearDailyStatusStore();
  }

  Future<void> _saveDailyStatus(DailyAttendanceStatus status) async {
    final store = statusStore;
    if (store == null) return;
    try {
      await _enqueueStatusStoreOperation(() => store.save(status));
    } catch (_) {
      // Saving display-only cache data must not change server success state.
    }
  }

  void _clearDailyStatusStore() {
    final store = statusStore;
    if (store == null) return;
    unawaited(
      _ignoreStatusStoreErrors(_enqueueStatusStoreOperation(store.clear)),
    );
  }

  Future<void> _enqueueStatusStoreOperation(Future<void> Function() operation) {
    final queued = _statusStoreOperation.then((_) => operation());
    _statusStoreOperation = queued.catchError((_) {});
    return queued;
  }

  Future<void> _ignoreStatusStoreErrors(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // The session is already cleared in memory.
    }
  }

  DateTime _koreaDate(DateTime value) {
    final koreaTime = value.toUtc().add(const Duration(hours: 9));
    return DateTime.utc(koreaTime.year, koreaTime.month, koreaTime.day);
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

  Future<void> _rememberScheduledOccurrence(
    String scheduleId,
    DateTime scheduledAt,
  ) async {
    final now = DateTime.now();
    _completedOccurrences = await completionStore?.loadFor(now) ?? {};
    if (!isSameDate(scheduledAt, now) ||
        scheduledAt.isAfter(now.add(const Duration(minutes: 2)))) {
      notifyListeners();
      return;
    }
    final key = AttendanceCompletionStore.occurrenceKey(
      scheduleId,
      scheduledAt,
    );
    _completedOccurrences[key] = now;
    await completionStore?.save(_completedOccurrences);
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionRevision++;
    _awaitingAuthenticationCallback = false;
    _gateway.close();
    super.dispose();
  }
}

enum _AttendanceRecovery { authenticate, refresh }

sealed class _AttendanceRequest {
  const _AttendanceRequest();
}

final class _StatusRefreshRequest extends _AttendanceRequest {
  const _StatusRefreshRequest();
}

final class _ActionRequest extends _AttendanceRequest {
  const _ActionRequest(this.action);

  final AttendanceAction action;
}

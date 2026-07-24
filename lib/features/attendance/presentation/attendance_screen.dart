import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../../profile/domain/user_profile.dart';
import '../../schedule/application/schedule_controller.dart';
import '../../schedule/application/notification_scheduler.dart';
import '../../schedule/domain/attendance_schedule.dart';
import '../../schedule/domain/training_calendar.dart';
import '../../schedule/presentation/schedule_list_screen.dart';
import '../application/attendance_controller.dart';
import '../data/attendance_completion_store.dart';
import '../data/attendance_gateway.dart';
import '../data/attendance_status_store.dart';
import '../data/callback_link_settings.dart';
import '../data/skala_attendance_api.dart';
import '../domain/action_confirmation_policy.dart';
import '../domain/attendance_snapshot.dart';
import '../domain/daily_attendance_status.dart';
import '../domain/today_schedule_status.dart';
import 'attendance_display_formatter.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.profile,
    required this.scheduleController,
    required this.notificationScheduler,
    required this.onEditProfile,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.gateway,
    this.appLinkStream,
    this.isAndroid,
    this.callbackLinkSettings,
    this.statusStore,
    this.now,
  });

  final UserProfile profile;
  final ScheduleController scheduleController;
  final NotificationScheduler notificationScheduler;
  final Future<void> Function() onEditProfile;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final AttendanceGateway? gateway;
  final Stream<Uri>? appLinkStream;
  final bool? isAndroid;
  final CallbackLinkSettings? callbackLinkSettings;
  final AttendanceStatusStore? statusStore;
  final DateTime Function()? now;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with WidgetsBindingObserver {
  late final AttendanceController _controller;
  StreamSubscription<Uri>? _linkSubscription;
  late final CallbackLinkSettings _callbackLinkSettings;
  int _authenticationContinuationRevision = 0;
  int? _pendingSettingsContinuation;
  bool _authenticationFlowLocked = false;
  bool _handlingNotificationTap = false;
  bool _presentingReadyAction = false;
  int _handledReadyActionRevision = 0;
  int _handledStatusRevision = 0;
  int _handledCompletionRevision = 0;
  bool _showRecentlyUpdated = false;
  AttendanceAction? _highlightedAction;
  Timer? _recentlyUpdatedTimer;
  Timer? _actionHighlightTimer;
  Timer? _dailyExpiryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _callbackLinkSettings =
        widget.callbackLinkSettings ??
        PlatformCallbackLinkSettings(isAndroid: widget.isAndroid);
    _controller = AttendanceController(
      widget.profile,
      widget.gateway ?? SkalaAttendanceApi(),
      isAndroid: widget.isAndroid,
      completionStore: AttendanceCompletionStore(),
      statusStore: widget.statusStore ?? AttendanceStatusStore(),
      now: widget.now,
    );
    _controller.addListener(_handleControllerChange);
    unawaited(_controller.loadCompletionHistory());
    unawaited(_controller.loadDailyStatus());
    _scheduleDailyExpiry();
    widget.scheduleController.addListener(_handleNotificationTap);
    _linkSubscription = (widget.appLinkStream ?? AppLinks().uriLinkStream)
        .listen(_handleAppLink, onError: _handleAppLinkError);
    widget.notificationScheduler.tapPayload.addListener(_handleNotificationTap);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleNotificationTap(),
    );
  }

  Future<void> _handleAppLink(Uri uri) async {
    _invalidateAuthenticationContinuation();
    await _controller.handleCallback(uri);
  }

  void _handleAppLinkError(Object error, [StackTrace? stackTrace]) {
    _invalidateAuthenticationContinuation();
    _controller.reportLinkError(error);
  }

  void _handleNotificationTap() {
    final payload = widget.notificationScheduler.tapPayload.value;
    if (!mounted ||
        payload == null ||
        widget.scheduleController.loading ||
        _attendanceInteractionLocked ||
        _handlingNotificationTap) {
      return;
    }
    _handlingNotificationTap = true;
    widget.notificationScheduler.consumeTap();
    final occurrence = _occurrenceFromPayload(payload);
    if (occurrence == null) {
      _handlingNotificationTap = false;
      return;
    }
    if (!_isCurrentScheduledOccurrence(occurrence)) {
      _controller.reportStaleScheduledOccurrence();
      _handlingNotificationTap = false;
      return;
    }
    unawaited(
      _beginAction(
        occurrence.action,
        scheduleId: occurrence.scheduleId,
        scheduledAt: occurrence.scheduledAt,
      ).whenComplete(() {
        _handlingNotificationTap = false;
        _handleNotificationTap();
      }),
    );
  }

  Future<void> _beginAction(
    AttendanceAction action, {
    String? scheduleId,
    DateTime? scheduledAt,
  }) async {
    if (_attendanceInteractionLocked) return;
    final result = await _controller.requestAction(
      action,
      scheduleId: scheduleId,
      scheduledAt: scheduledAt,
    );
    if (result == AttendanceRequestResult.authenticationRequired) {
      await _requestAuthentication();
    }
  }

  Future<void> _refreshStatus() async {
    if (_attendanceInteractionLocked) return;
    final result = await _controller.requestStatusRefresh();
    if (result == AttendanceRequestResult.authenticationRequired) {
      await _requestAuthentication();
    }
  }

  Future<void> _requestAuthentication() async {
    if (_authenticationFlowLocked ||
        _controller.busy ||
        _controller.awaitingAuthenticationCallback ||
        _controller.readyAction != null ||
        _presentingReadyAction) {
      return;
    }
    final continuationRevision = ++_authenticationContinuationRevision;
    _pendingSettingsContinuation = null;
    _setAuthenticationFlowLocked(true);
    try {
      final linkEnabled =
          widget.isAndroid == false || await _callbackLinkSettings.isEnabled();
      if (!_authenticationContinuationIsCurrent(continuationRevision)) return;
      if (!mounted) return;
      if (linkEnabled) {
        await _startAuthenticationContinuation(continuationRevision);
        return;
      }
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('앱 복귀 설정이 필요합니다'),
          content: const Text(
            'Google 인증이 끝난 뒤 이 앱으로 자동 복귀하려면 '
            '지원되는 링크 열기를 허용해야 합니다.\n\n'
            '설정 화면에서 지원되는 링크 열기를 활성화해 주세요. '
            '이 설정은 최초 한 번만 필요합니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('링크 설정 열기'),
            ),
          ],
        ),
      );
      if (!_authenticationContinuationIsCurrent(continuationRevision)) return;
      if (openSettings != true) {
        _controller.cancelPendingRequest();
        _finishAuthenticationContinuation(continuationRevision);
        return;
      }
      _pendingSettingsContinuation = continuationRevision;
      await _callbackLinkSettings.open();
    } catch (error) {
      if (!_authenticationContinuationIsCurrent(continuationRevision)) return;
      _handleAppLinkError(error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_invalidateExpiredDailyState()) return;
      if (_pendingSettingsContinuation != null) {
        unawaited(_resumeAuthenticationAfterSettings());
      } else {
        _controller.startAuthenticationCallbackGrace();
      }
    }
  }

  Future<void> _resumeAuthenticationAfterSettings() async {
    final continuationRevision = _pendingSettingsContinuation;
    if (continuationRevision == null) return;
    try {
      final linkEnabled = await _callbackLinkSettings.isEnabled();
      if (!_authenticationContinuationIsCurrent(
        continuationRevision,
        requireSettingsContinuation: true,
      )) {
        return;
      }
      if (!linkEnabled) {
        _controller.cancelPendingRequest();
        _finishAuthenticationContinuation(continuationRevision);
        return;
      }
      _pendingSettingsContinuation = null;
      await _startAuthenticationContinuation(continuationRevision);
    } catch (error) {
      if (!_authenticationContinuationIsCurrent(
        continuationRevision,
        requireSettingsContinuation: true,
      )) {
        return;
      }
      _handleAppLinkError(error);
    }
  }

  Future<void> _startAuthenticationContinuation(int revision) async {
    if (!_authenticationContinuationIsCurrent(revision)) return;
    await _controller.startAuthentication();
    _finishAuthenticationContinuation(revision);
  }

  bool _authenticationContinuationIsCurrent(
    int revision, {
    bool requireSettingsContinuation = false,
  }) {
    return mounted &&
        revision == _authenticationContinuationRevision &&
        (!requireSettingsContinuation ||
            _pendingSettingsContinuation == revision);
  }

  bool get _attendanceInteractionLocked =>
      _authenticationFlowLocked ||
      _controller.busy ||
      _controller.awaitingAuthenticationCallback ||
      _controller.readyAction != null ||
      _presentingReadyAction;

  void _setAuthenticationFlowLocked(bool locked) {
    if (_authenticationFlowLocked == locked) return;
    if (mounted) {
      setState(() => _authenticationFlowLocked = locked);
    } else {
      _authenticationFlowLocked = locked;
    }
  }

  void _finishAuthenticationContinuation(int revision) {
    if (revision != _authenticationContinuationRevision) return;
    _pendingSettingsContinuation = null;
    _setAuthenticationFlowLocked(false);
    _handleNotificationTap();
  }

  void _invalidateAuthenticationContinuation({bool notify = true}) {
    _authenticationContinuationRevision++;
    _pendingSettingsContinuation = null;
    if (!_authenticationFlowLocked) return;
    if (notify && mounted) {
      setState(() => _authenticationFlowLocked = false);
    } else {
      _authenticationFlowLocked = false;
    }
  }

  bool _invalidateExpiredDailyState() =>
      _controller.invalidateExpiredDailyState(
        beforeInvalidation: _invalidateAuthenticationContinuation,
      );

  Future<void> _retry() async {
    if (_attendanceInteractionLocked) return;
    if (_controller.retryRequiresAuthentication) {
      await _requestAuthentication();
    } else {
      await _controller.retry();
    }
  }

  _ScheduledOccurrence? _occurrenceFromPayload(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final scheduleId = json['scheduleId'] as String?;
      final actionName = json['action'] as String?;
      final scheduledAtValue = json['scheduledAt'] as String?;
      if (scheduleId == null ||
          actionName == null ||
          scheduledAtValue == null) {
        return null;
      }
      final action = AttendanceAction.values
          .where((action) => action.name == actionName)
          .firstOrNull;
      final scheduledAt = DateTime.tryParse(scheduledAtValue);
      if (action == null || scheduledAt == null) return null;
      return (scheduleId: scheduleId, action: action, scheduledAt: scheduledAt);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  bool _isCurrentScheduledOccurrence(_ScheduledOccurrence occurrence) {
    final matchingSchedules = widget.scheduleController.schedulesFor(
      occurrence.scheduledAt,
    );
    return matchingSchedules.any(
      (schedule) =>
          schedule.id == occurrence.scheduleId &&
          schedule.action == occurrence.action &&
          schedule.hour == occurrence.scheduledAt.hour &&
          schedule.minute == occurrence.scheduledAt.minute,
    );
  }

  void _handleControllerChange() {
    _consumeControllerEvents();
    _consumeReadyAction();
    _handleNotificationTap();
  }

  void _consumeReadyAction() {
    final action = _controller.readyAction;
    final revision = _controller.readyActionRevision;
    if (action == null ||
        _controller.busy ||
        _authenticationFlowLocked ||
        _presentingReadyAction ||
        revision <= _handledReadyActionRevision) {
      return;
    }
    _handledReadyActionRevision = revision;
    _presentingReadyAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        await _confirmAction(action, revision);
      } finally {
        _presentingReadyAction = false;
        _consumeReadyAction();
        _handleNotificationTap();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _consumeControllerEvents() {
    if (_controller.snapshot == null &&
        _controller.lastCompletedAction == null) {
      _showRecentlyUpdated = false;
      _highlightedAction = null;
      _recentlyUpdatedTimer?.cancel();
      _actionHighlightTimer?.cancel();
    }

    if (_controller.statusRevision > _handledStatusRevision) {
      _handledStatusRevision = _controller.statusRevision;
      _showRecentlyUpdated = true;
      _recentlyUpdatedTimer?.cancel();
      final revision = _handledStatusRevision;
      _recentlyUpdatedTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted || revision != _handledStatusRevision) return;
        setState(() => _showRecentlyUpdated = false);
      });
      _scheduleDailyExpiry();
    }

    if (_controller.completionRevision <= _handledCompletionRevision) return;
    _handledCompletionRevision = _controller.completionRevision;
    final completedAction = _controller.lastCompletedAction;
    if (completedAction == null) return;

    _highlightedAction = completedAction;
    _actionHighlightTimer?.cancel();
    final revision = _handledCompletionRevision;
    _actionHighlightTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || revision != _handledCompletionRevision) return;
      setState(() => _highlightedAction = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _handledCompletionRevision) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(_completionMessage(completedAction))),
        );
    });
  }

  void _scheduleDailyExpiry() {
    _dailyExpiryTimer?.cancel();
    final utcNow = (widget.now ?? DateTime.now)().toUtc();
    final koreaNow = utcNow.add(const Duration(hours: 9));
    final nextKoreaDate = DateTime.utc(
      koreaNow.year,
      koreaNow.month,
      koreaNow.day + 1,
    );
    final nextKoreaMidnightUtc = nextKoreaDate.subtract(
      const Duration(hours: 9),
    );
    final remaining = nextKoreaMidnightUtc.difference(utcNow);
    _dailyExpiryTimer = Timer(
      remaining > Duration.zero ? remaining : Duration.zero,
      () {
        if (!mounted) return;
        _invalidateExpiredDailyState();
        _scheduleDailyExpiry();
      },
    );
  }

  @override
  void didUpdateWidget(covariant AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _invalidateAuthenticationContinuation(notify: false);
      _controller.updateProfile(widget.profile);
    }
  }

  @override
  void dispose() {
    _invalidateAuthenticationContinuation(notify: false);
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    widget.notificationScheduler.tapPayload.removeListener(
      _handleNotificationTap,
    );
    widget.scheduleController.removeListener(_handleNotificationTap);
    _controller.removeListener(_handleControllerChange);
    _recentlyUpdatedTimer?.cancel();
    _actionHighlightTimer?.cancel();
    _dailyExpiryTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmAction(
    AttendanceAction action,
    int readyActionRevision,
  ) async {
    if (!requiresAttendanceConfirmation(action)) {
      await _controller.performAction(
        action,
        readyActionRevision: readyActionRevision,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => action == AttendanceAction.checkOut
          ? _EarlyCheckOutConfirmationDialog(profileName: widget.profile.name)
          : AlertDialog(
              title: Text('${action.label} 처리'),
              content: Text(
                '${widget.profile.name}님, ${attendanceConfirmationMessage(action)}\n\n'
                '전송된 출결 기록은 앱에서 취소할 수 없습니다.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text('${action.label} 전송'),
                ),
              ],
            ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      await _controller.performAction(
        action,
        readyActionRevision: readyActionRevision,
      );
    } else if (_controller.readyAction == action &&
        _controller.readyActionRevision == readyActionRevision) {
      _controller.cancelReadyAction();
    }
  }

  Future<void> _showThemePicker() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('테마 선택'),
        children: ThemeMode.values.map((mode) {
          final (icon, label) = switch (mode) {
            ThemeMode.system => (Icons.settings_suggest_outlined, '시스템 설정'),
            ThemeMode.light => (Icons.light_mode_outlined, '라이트 모드'),
            ThemeMode.dark => (Icons.dark_mode_outlined, '다크 모드'),
          };
          return SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(mode),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(label),
              trailing: widget.themeMode == mode
                  ? const Icon(Icons.check)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
    if (selected != null) widget.onThemeModeChanged?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final attendanceBusy =
            _authenticationFlowLocked ||
            _controller.busy ||
            _controller.awaitingAuthenticationCallback;
        final attendanceLocked = _attendanceInteractionLocked;
        return Scaffold(
          appBar: AppBar(
            title: const Text('SKALA 출결'),
            actions: [
              if (widget.onThemeModeChanged != null)
                IconButton(
                  tooltip: '테마 설정',
                  onPressed: _showThemePicker,
                  icon: const Icon(Icons.brightness_6_outlined),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                '${widget.profile.name}님, 안녕하세요',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '오늘의 출결 일정과 상태를 확인하세요.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _ProfileCard(
                profile: widget.profile,
                busy: attendanceLocked,
                onEditProfile: widget.onEditProfile,
              ),
              const SizedBox(height: 16),
              _StatusCard(
                status: _controller.dailyStatus,
                liveSnapshot: _controller.snapshot,
                busy: attendanceBusy,
                interactionLocked: attendanceLocked,
                showRecentlyUpdated: _showRecentlyUpdated,
                highlightedAction: _highlightedAction,
                message: _controller.message,
                hasError: _controller.hasError,
                canRetry: _controller.canRetry,
                retryLabel: _controller.retryLabel,
                onRefresh: _refreshStatus,
                onAction: _beginAction,
                onRetry: _retry,
              ),
              const SizedBox(height: 16),
              _TodaySchedulesCard(
                controller: widget.scheduleController,
                attendanceController: _controller,
              ),
              const SizedBox(height: 24),
              Text(
                'Google 인증은 브라우저에서 직접 진행하며 인증 정보는 기기에 저장하지 않습니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _completionMessage(AttendanceAction action) {
  return switch (action) {
    AttendanceAction.checkIn => '입실이 완료되었습니다.',
    AttendanceAction.checkOut => '퇴실이 완료되었습니다.',
    AttendanceAction.leave => '외출이 완료되었습니다.',
    AttendanceAction.returnFromLeave => '복귀가 완료되었습니다.',
  };
}

class _EarlyCheckOutConfirmationDialog extends StatefulWidget {
  const _EarlyCheckOutConfirmationDialog({required this.profileName});

  final String profileName;

  @override
  State<_EarlyCheckOutConfirmationDialog> createState() =>
      _EarlyCheckOutConfirmationDialogState();
}

class _EarlyCheckOutConfirmationDialogState
    extends State<_EarlyCheckOutConfirmationDialog> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = timeUntilConfirmationFreeCheckOut(_now);
    final reachedThreshold = remaining == Duration.zero;
    return AlertDialog(
      title: const Text('퇴실 처리'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reachedThreshold
                ? '${widget.profileName}님, 퇴실 가능 시간이 되었습니다.'
                : '${widget.profileName}님, 아직 오후 5시 50분 이전입니다.',
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  formatRemainingClock(remaining),
                  key: const Key('check-out-countdown'),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reachedThreshold ? '지금부터 확인 없이 퇴실 가능' : '안전한 퇴실까지 남은 시간',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(reachedThreshold ? '퇴실 기록을 전송하시겠습니까?' : '지금 퇴실 처리하시겠습니까?'),
          const SizedBox(height: 8),
          Text(
            '전송된 출결 기록은 앱에서 취소할 수 없습니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('퇴실 전송'),
        ),
      ],
    );
  }
}

class _TodaySchedulesCard extends StatefulWidget {
  const _TodaySchedulesCard({
    required this.controller,
    required this.attendanceController,
  });

  final ScheduleController controller;
  final AttendanceController attendanceController;

  @override
  State<_TodaySchedulesCard> createState() => _TodaySchedulesCardState();
}

class _TodaySchedulesCardState extends State<_TodaySchedulesCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final today = DateTime.now();
        final schedules = widget.controller.schedulesFor(today);
        final holidayName = TrainingCalendar.holidayName(today);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.event_available_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '오늘 예정된 동작',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await widget.controller.refreshNotificationStatus();
                        if (!context.mounted) return;
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ScheduleListScreen(
                              controller: widget.controller,
                            ),
                          ),
                        );
                      },
                      child: const Text('일정 관리'),
                    ),
                  ],
                ),
                if (widget.controller.loading)
                  const LinearProgressIndicator()
                else if (holidayName != null && schedules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('$holidayName · 반복 일정이 제외되었습니다.'),
                  )
                else if (schedules.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('오늘 실행할 일정이 없습니다.'),
                  )
                else
                  ...schedules.map((schedule) {
                    final status = statusForTodaySchedule(
                      schedule,
                      now: today,
                      persistedCompleted: widget.attendanceController
                          .wasScheduleCompleted(schedule, today),
                      persistedSkipped: widget.attendanceController
                          .wasScheduleSkipped(schedule, today),
                    );
                    return _ScheduleRow(
                      schedule,
                      status: status,
                      onStatusTap:
                          status == TodayScheduleStatus.overdue ||
                              status == TodayScheduleStatus.skipped
                          ? () => _changeSkippedStatus(schedule, status, today)
                          : null,
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _changeSkippedStatus(
    AttendanceSchedule schedule,
    TodayScheduleStatus status,
    DateTime date,
  ) async {
    final markingSkipped = status == TodayScheduleStatus.overdue;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(markingSkipped ? '이 동작을 건너뛸까요?' : '건너뜀을 취소할까요?'),
        content: Text(
          markingSkipped
              ? '수행할 필요가 없었던 일정이라면 건너뜀으로 표시할 수 있습니다. 실제 출결 완료로 기록되지는 않습니다.'
              : '이 일정을 다시 시간 지남 상태로 되돌립니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(markingSkipped ? '건너뜀으로 표시' : '되돌리기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.attendanceController.setScheduleSkipped(
      schedule,
      date,
      skipped: markingSkipped,
    );
  }
}

typedef _ScheduledOccurrence = ({
  String scheduleId,
  AttendanceAction action,
  DateTime scheduledAt,
});

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow(this.schedule, {required this.status, this.onStatusTap});

  final AttendanceSchedule schedule;
  final TodayScheduleStatus status;
  final VoidCallback? onStatusTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completedColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);
    final (icon, label, color) = switch (status) {
      TodayScheduleStatus.upcoming => (
        Icons.schedule_outlined,
        '예정',
        colors.primary,
      ),
      TodayScheduleStatus.completed => (
        Icons.check_circle_outline_rounded,
        '완료',
        completedColor,
      ),
      TodayScheduleStatus.skipped => (
        Icons.do_not_disturb_on_outlined,
        '건너뜀',
        colors.outline,
      ),
      TodayScheduleStatus.overdue => (
        Icons.history_toggle_off_rounded,
        '시간 지남',
        colors.error,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Text(schedule.displayTime),
          const SizedBox(width: 12),
          Expanded(child: Text(schedule.action.label)),
          InkWell(
            onTap: onStatusTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.busy,
    required this.onEditProfile,
  });

  final UserProfile profile;
  final bool busy;
  final Future<void> Function() onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${profile.region.label} · ${profile.classLabel}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: busy ? null : onEditProfile,
              child: const Text('사용자 정보 변경'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.liveSnapshot,
    required this.busy,
    required this.interactionLocked,
    required this.showRecentlyUpdated,
    required this.highlightedAction,
    required this.message,
    required this.hasError,
    required this.canRetry,
    required this.retryLabel,
    required this.onRefresh,
    required this.onAction,
    required this.onRetry,
  });

  final DailyAttendanceStatus status;
  final AttendanceSnapshot? liveSnapshot;
  final bool busy;
  final bool interactionLocked;
  final bool showRecentlyUpdated;
  final AttendanceAction? highlightedAction;
  final String message;
  final bool hasError;
  final bool canRetry;
  final String retryLabel;
  final Future<void> Function() onRefresh;
  final Future<void> Function(AttendanceAction action) onAction;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final availableActions = status.queried
        ? status.sequenceAvailableActions
        : AttendanceAction.values.toSet();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '오늘 출결 · ${formatAttendanceDate(status.koreaDate)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '출결 상태 새로고침',
                  onPressed: interactionLocked ? null : onRefresh,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (showRecentlyUpdated) ...[
              const SizedBox(height: 4),
              Text(
                '방금 업데이트됨',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _AttendanceStatusTiles(
              status: status,
              highlightedAction: highlightedAction,
            ),
            const SizedBox(height: 16),
            if (message.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasError
                      ? colors.errorContainer.withValues(alpha: 0.65)
                      : colors.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message,
                  style: TextStyle(
                    color: hasError
                        ? colors.onErrorContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (hasError && canRetry) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: interactionLocked ? null : onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(retryLabel),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
            if (liveSnapshot?.networkAllowed == false) ...[
              Text(
                '현재 네트워크에서는 출결 동작을 전송할 수 없습니다.',
                style: TextStyle(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (availableActions.isEmpty)
              const Text('현재 가능한 출결 동작이 없습니다.')
            else ...[
              Text('가능한 동작', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableActions.map((action) {
                  return FilledButton.tonal(
                    onPressed: interactionLocked
                        ? null
                        : () => onAction(action),
                    child: Text(action.label),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttendanceStatusTiles extends StatelessWidget {
  const _AttendanceStatusTiles({
    required this.status,
    required this.highlightedAction,
  });

  final DailyAttendanceStatus status;
  final AttendanceAction? highlightedAction;

  @override
  Widget build(BuildContext context) {
    final statuses = [
      (AttendanceAction.checkIn, status.checkInTime),
      (AttendanceAction.checkOut, status.checkOutTime),
      (AttendanceAction.leave, status.earlyLeaveTime),
      (AttendanceAction.returnFromLeave, status.returnTime),
    ];
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        const minimumTileWidth = 132.0;
        final twoColumnTileWidth = (constraints.maxWidth - spacing) / 2;
        final useTwoColumns =
            twoColumnTileWidth >= minimumTileWidth &&
            textScaler.scale(16) <= 20;
        final tileWidth = useTwoColumns
            ? twoColumnTileWidth
            : constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: statuses.map((status) {
            return SizedBox(
              width: tileWidth,
              child: _AttendanceStatusTile(
                action: status.$1,
                value: status.$2,
                queried: this.status.queried,
                highlighted: highlightedAction == status.$1,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _AttendanceStatusTile extends StatelessWidget {
  const _AttendanceStatusTile({
    required this.action,
    required this.value,
    required this.queried,
    required this.highlighted,
  });

  final AttendanceAction action;
  final String? value;
  final bool queried;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      key: ValueKey('attendance-status-${action.name}'),
      duration: const Duration(milliseconds: 250),
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.primaryContainer.withValues(alpha: 0.8)
            : colors.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(
          color: highlighted ? colors.primary : colors.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            action.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            queried ? formatAttendanceTime(value) : '확인 전',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          ),
          if (highlighted) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '방금 처리됨',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

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
import '../data/callback_link_settings.dart';
import '../data/attendance_gateway.dart';
import '../data/skala_attendance_api.dart';
import '../domain/action_confirmation_policy.dart';
import '../domain/attendance_snapshot.dart';
import '../domain/today_schedule_status.dart';

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

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with WidgetsBindingObserver {
  late final AttendanceController _controller;
  StreamSubscription<Uri>? _linkSubscription;
  AttendanceAction? _pendingScheduledAction;
  bool _handlingScheduledAction = false;
  late final CallbackLinkSettings _callbackLinkSettings;
  _PendingAuthentication? _pendingAuthentication;

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
    );
    unawaited(_controller.loadCompletionHistory());
    _controller.addListener(_handleControllerChange);
    _linkSubscription = (widget.appLinkStream ?? AppLinks().uriLinkStream)
        .listen(
          _controller.handleCallback,
          onError: _controller.reportLinkError,
        );
    widget.notificationScheduler.tapPayload.addListener(_handleNotificationTap);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleNotificationTap(),
    );
  }

  void _handleNotificationTap() {
    final payload = widget.notificationScheduler.tapPayload.value;
    if (payload == null || _controller.busy) return;
    widget.notificationScheduler.consumeTap();
    final occurrence = _occurrenceFromPayload(payload);
    if (occurrence == null) return;
    _pendingScheduledAction = occurrence.action;
    unawaited(
      _requestAuthentication(
        scheduleId: occurrence.scheduleId,
        scheduledAt: occurrence.scheduledAt,
      ),
    );
  }

  Future<void> _requestAuthentication({
    String? scheduleId,
    DateTime? scheduledAt,
  }) async {
    if (widget.isAndroid == false || await _callbackLinkSettings.isEnabled()) {
      await _controller.startAuthentication(
        scheduleId: scheduleId,
        scheduledAt: scheduledAt,
      );
      return;
    }
    if (!mounted) return;
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
    if (openSettings != true) {
      _pendingScheduledAction = null;
      return;
    }
    _pendingAuthentication = (scheduleId: scheduleId, scheduledAt: scheduledAt);
    await _callbackLinkSettings.open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeAuthenticationAfterSettings());
    }
  }

  Future<void> _resumeAuthenticationAfterSettings() async {
    final pending = _pendingAuthentication;
    if (pending == null || !await _callbackLinkSettings.isEnabled()) return;
    _pendingAuthentication = null;
    await _controller.startAuthentication(
      scheduleId: pending.scheduleId,
      scheduledAt: pending.scheduledAt,
    );
  }

  Future<void> _retry() async {
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

  void _handleControllerChange() {
    final action = _pendingScheduledAction;
    final snapshot = _controller.snapshot;
    if (action == null ||
        snapshot == null ||
        !_controller.authenticated ||
        _controller.busy ||
        _handlingScheduledAction) {
      return;
    }
    _pendingScheduledAction = null;
    _handlingScheduledAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (snapshot.availableActions.contains(action)) {
        await _confirmAction(action);
      } else {
        _controller.reportUnavailableScheduledAction(action);
      }
      _handlingScheduledAction = false;
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didUpdateWidget(covariant AttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile != widget.profile) {
      _controller.updateProfile(widget.profile);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    widget.notificationScheduler.tapPayload.removeListener(
      _handleNotificationTap,
    );
    _controller.removeListener(_handleControllerChange);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmAction(AttendanceAction action) async {
    if (!requiresAttendanceConfirmation(action)) {
      await _controller.performAction(action);
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
    if (confirmed == true) await _controller.performAction(action);
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
                busy: _controller.busy,
                onEditProfile: widget.onEditProfile,
              ),
              const SizedBox(height: 16),
              _TodaySchedulesCard(
                controller: widget.scheduleController,
                attendanceController: _controller,
              ),
              const SizedBox(height: 16),
              _AuthenticationCard(
                busy: _controller.busy,
                message: _controller.message,
                authenticated: _controller.authenticated,
                hasError: _controller.hasError,
                canRetry: _controller.canRetry,
                retryLabel: _controller.retryLabel,
                onAuthenticate: _requestAuthentication,
                onRetry: _retry,
              ),
              if (_controller.snapshot case final snapshot?) ...[
                const SizedBox(height: 16),
                _StatusCard(
                  snapshot: snapshot,
                  busy: _controller.busy,
                  onAction: _confirmAction,
                ),
              ],
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

typedef _PendingAuthentication = ({String? scheduleId, DateTime? scheduledAt});

class _AuthenticationCard extends StatelessWidget {
  const _AuthenticationCard({
    required this.busy,
    required this.message,
    required this.authenticated,
    required this.hasError,
    required this.canRetry,
    required this.retryLabel,
    required this.onAuthenticate,
    required this.onRetry,
  });

  final bool busy;
  final String message;
  final bool authenticated;
  final bool hasError;
  final bool canRetry;
  final String retryLabel;
  final Future<void> Function() onAuthenticate;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: hasError
          ? colors.errorContainer.withValues(alpha: 0.55)
          : authenticated
          ? colors.primaryContainer.withValues(alpha: 0.55)
          : colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: hasError
                      ? colors.error
                      : authenticated
                      ? colors.primary
                      : colors.secondaryContainer,
                  foregroundColor: hasError
                      ? colors.onError
                      : authenticated
                      ? colors.onPrimary
                      : colors.onSecondaryContainer,
                  child: Icon(
                    hasError
                        ? Icons.error_outline_rounded
                        : authenticated
                        ? Icons.verified_user_outlined
                        : Icons.lock_person_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasError
                            ? '다시 확인이 필요합니다'
                            : authenticated
                            ? '오늘 인증 완료'
                            : 'Google 인증 필요',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy
                    ? null
                    : canRetry
                    ? onRetry
                    : onAuthenticate,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_browser_outlined),
                label: Text(
                  canRetry
                      ? retryLabel
                      : authenticated
                      ? '다시 인증하기'
                      : 'Google 인증 시작',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                  ...schedules.map(
                    (schedule) => _ScheduleRow(
                      schedule,
                      status: statusForTodaySchedule(
                        schedule,
                        now: today,
                        persistedCompleted: widget.attendanceController
                            .wasScheduleCompleted(schedule, today),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

typedef _ScheduledOccurrence = ({
  String scheduleId,
  AttendanceAction action,
  DateTime scheduledAt,
});

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow(this.schedule, {required this.status});

  final AttendanceSchedule schedule;
  final TodayScheduleStatus status;

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
          Container(
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
    required this.snapshot,
    required this.busy,
    required this.onAction,
  });

  final AttendanceSnapshot snapshot;
  final bool busy;
  final Future<void> Function(AttendanceAction action) onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('오늘 출결', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('네트워크 허용: ${snapshot.networkAllowed ? '예' : '아니오'}'),
            Text('입실: ${snapshot.checkInTime ?? '없음'}'),
            Text('퇴실: ${snapshot.checkOutTime ?? '없음'}'),
            Text('외출: ${snapshot.earlyLeaveTime ?? '없음'}'),
            Text('복귀: ${snapshot.returnTime ?? '없음'}'),
            const SizedBox(height: 16),
            if (!snapshot.networkAllowed)
              const Text('현재 네트워크에서는 출결 동작을 전송할 수 없습니다.')
            else if (snapshot.availableActions.isEmpty)
              const Text('현재 가능한 출결 동작이 없습니다.')
            else ...[
              Text('가능한 동작', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: snapshot.availableActions.map((action) {
                  return FilledButton.tonal(
                    onPressed: busy ? null : () => onAction(action),
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

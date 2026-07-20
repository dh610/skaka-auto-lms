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
import '../data/attendance_gateway.dart';
import '../data/skala_attendance_api.dart';
import '../domain/action_confirmation_policy.dart';
import '../domain/attendance_snapshot.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.profile,
    required this.scheduleController,
    required this.notificationScheduler,
    required this.onEditProfile,
    this.gateway,
    this.appLinkStream,
    this.isAndroid,
  });

  final UserProfile profile;
  final ScheduleController scheduleController;
  final NotificationScheduler notificationScheduler;
  final Future<void> Function() onEditProfile;
  final AttendanceGateway? gateway;
  final Stream<Uri>? appLinkStream;
  final bool? isAndroid;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final AttendanceController _controller;
  StreamSubscription<Uri>? _linkSubscription;
  AttendanceAction? _pendingScheduledAction;
  bool _handlingScheduledAction = false;

  @override
  void initState() {
    super.initState();
    _controller = AttendanceController(
      widget.profile,
      widget.gateway ?? SkalaAttendanceApi(),
      isAndroid: widget.isAndroid,
    );
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
    final action = _actionFromPayload(payload);
    if (action == null) return;
    _pendingScheduledAction = action;
    _controller.startAuthentication();
  }

  AttendanceAction? _actionFromPayload(String payload) {
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      final actionName = json['action'] as String?;
      if (actionName == null) return null;
      return AttendanceAction.values
          .where((action) => action.name == actionName)
          .firstOrNull;
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('SKALA 출결')),
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
              _TodaySchedulesCard(controller: widget.scheduleController),
              const SizedBox(height: 16),
              _AuthenticationCard(
                busy: _controller.busy,
                message: _controller.message,
                authenticated: _controller.authenticated,
                hasError: _controller.hasError,
                canRetry: _controller.canRetry,
                retryLabel: _controller.retryLabel,
                onAuthenticate: _controller.startAuthentication,
                onRetry: _controller.retry,
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
      content: Text(
        reachedThreshold
            ? '${widget.profileName}님, 퇴실 가능 시간이 되었습니다.\n\n'
                  '전송된 출결 기록은 앱에서 취소할 수 없습니다.'
            : '${widget.profileName}님, 아직 오후 5시 50분 이전입니다.\n'
                  '오후 5시 50분까지 ${formatRemainingTime(remaining)} 남았습니다.\n'
                  '정말 퇴실 처리하시겠습니까?\n\n'
                  '전송된 출결 기록은 앱에서 취소할 수 없습니다.',
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

class _TodaySchedulesCard extends StatelessWidget {
  const _TodaySchedulesCard({required this.controller});

  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final today = DateTime.now();
        final schedules = controller.schedulesFor(today);
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
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              ScheduleListScreen(controller: controller),
                        ),
                      ),
                      child: const Text('일정 관리'),
                    ),
                  ],
                ),
                if (controller.loading)
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
                  ...schedules.map((schedule) => _ScheduleRow(schedule)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow(this.schedule);

  final AttendanceSchedule schedule;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 20),
          const SizedBox(width: 10),
          Text(schedule.displayTime),
          const SizedBox(width: 12),
          Text(schedule.action.label),
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

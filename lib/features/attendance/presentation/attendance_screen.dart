import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../../profile/domain/user_profile.dart';
import '../../schedule/application/schedule_controller.dart';
import '../../schedule/domain/attendance_schedule.dart';
import '../../schedule/domain/training_calendar.dart';
import '../../schedule/presentation/schedule_list_screen.dart';
import '../application/attendance_controller.dart';
import '../data/skala_attendance_api.dart';
import '../domain/attendance_snapshot.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.profile,
    required this.scheduleController,
    required this.onEditProfile,
  });

  final UserProfile profile;
  final ScheduleController scheduleController;
  final Future<void> Function() onEditProfile;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final AttendanceController _controller;
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _controller = AttendanceController(widget.profile, SkalaAttendanceApi());
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _controller.handleCallback,
      onError: _controller.reportLinkError,
    );
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('SKALA 출결 도우미')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _ProfileCard(
                profile: widget.profile,
                platformDescription: _controller.platformDescription,
                busy: _controller.busy,
                onEditProfile: widget.onEditProfile,
              ),
              const SizedBox(height: 16),
              _TodaySchedulesCard(controller: widget.scheduleController),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _controller.busy
                    ? null
                    : _controller.startAuthentication,
                icon: _controller.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Google 인증 시작'),
              ),
              const SizedBox(height: 16),
              Text(_controller.message),
              if (_controller.snapshot case final snapshot?) ...[
                const SizedBox(height: 16),
                _StatusCard(snapshot: snapshot),
              ],
              const SizedBox(height: 24),
              const Text('현재 버전은 읽기 전용입니다. 입실·퇴실·외출·복귀 요청을 전송하지 않습니다.'),
            ],
          ),
        );
      },
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
          Text(schedule.formattedTime),
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
    required this.platformDescription,
    required this.busy,
    required this.onEditProfile,
  });

  final UserProfile profile;
  final String platformDescription;
  final bool busy;
  final Future<void> Function() onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              platformDescription,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              '${profile.name} · ${profile.region.label} · ${profile.classLabel}',
            ),
            const Text('Google 계정은 브라우저에서 직접 선택합니다.'),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : onEditProfile,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('사용자 정보 변경'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.snapshot});

  final AttendanceSnapshot snapshot;

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
          ],
        ),
      ),
    );
  }
}

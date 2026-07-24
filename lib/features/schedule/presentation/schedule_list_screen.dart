import 'package:flutter/material.dart';

import '../application/schedule_controller.dart';
import '../domain/attendance_schedule.dart';
import 'schedule_edit_screen.dart';
import 'schedule_visuals.dart';

class ScheduleListScreen extends StatelessWidget {
  const ScheduleListScreen({super.key, required this.controller});

  final ScheduleController controller;

  Future<void> _openEditor(
    BuildContext context, [
    AttendanceSchedule? schedule,
  ]) async {
    final updated = await Navigator.of(context).push<AttendanceSchedule>(
      MaterialPageRoute(
        builder: (_) => ScheduleEditScreen(
          initialSchedule: schedule,
          initialAlarmSettings:
              schedule?.alarmSettings ?? controller.defaultAlarmSettings,
          onPickAlarmSound: controller.pickAlarmSound,
          existingSchedules: controller.schedules,
        ),
      ),
    );
    if (updated != null) {
      final conflict = await controller.saveSchedule(updated);
      if (conflict != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(conflict.message)));
      }
    }
  }

  Future<void> _setEnabled(
    BuildContext context,
    AttendanceSchedule schedule,
    bool enabled,
  ) async {
    final conflict = await controller.setEnabled(schedule, enabled);
    if (conflict != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(conflict.message)));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AttendanceSchedule schedule,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('일정 삭제'),
        content: Text(
          '${schedule.action.label} ${schedule.displayTime} 일정을 삭제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.delete(schedule);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('출결 일정 관리')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('일정 추가'),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 104),
            children: [
              if (!controller.notificationsConfigured) ...[
                _NotificationCard(controller: controller),
                const SizedBox(height: 24),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '내 일정',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${controller.schedules.length}개',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (controller.schedules.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 48,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_note_outlined,
                          size: 40,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '등록된 일정이 없습니다.\n일정 추가 버튼을 눌러 시작하세요.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...controller.schedules.map(
                  (schedule) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        enabled: schedule.enabled,
                        onTap: () => _openEditor(context, schedule),
                        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSecondaryContainer,
                          child: Icon(schedule.action.icon),
                        ),
                        title: Text(
                          '${schedule.displayTime} · ${schedule.action.label}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(schedule.recurrenceLabel),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: schedule.enabled,
                              onChanged: (enabled) =>
                                  _setEnabled(context, schedule, enabled),
                            ),
                            IconButton(
                              tooltip: '삭제',
                              onPressed: () =>
                                  _confirmDelete(context, schedule),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.controller});

  final ScheduleController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.notifications_active_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '일정 알림',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(controller.notificationMessage),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.configureNotifications,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('알림 권한 설정'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

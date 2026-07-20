import 'package:flutter/material.dart';

import '../application/schedule_controller.dart';
import '../domain/attendance_schedule.dart';
import 'schedule_edit_screen.dart';

class ScheduleListScreen extends StatelessWidget {
  const ScheduleListScreen({super.key, required this.controller});

  final ScheduleController controller;

  Future<void> _openEditor(
    BuildContext context, [
    AttendanceSchedule? schedule,
  ]) async {
    final updated = await Navigator.of(context).push<AttendanceSchedule>(
      MaterialPageRoute(
        builder: (_) => ScheduleEditScreen(initialSchedule: schedule),
      ),
    );
    if (updated != null) await controller.saveSchedule(updated);
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
          '${schedule.action.label} ${schedule.formattedTime} 일정을 삭제할까요?',
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              _NotificationCard(controller: controller),
              const SizedBox(height: 12),
              if (controller.schedules.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Text(
                    '등록된 일정이 없습니다.\n일정 추가 버튼을 눌러 시작하세요.',
                    textAlign: TextAlign.center,
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
                        leading: CircleAvatar(
                          child: Text(schedule.action.label[0]),
                        ),
                        title: Text(
                          '${schedule.formattedTime} · ${schedule.action.label}',
                        ),
                        subtitle: Text(schedule.recurrenceLabel),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: schedule.enabled,
                              onChanged: (enabled) =>
                                  controller.setEnabled(schedule, enabled),
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
            Text('일정 알림', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(controller.notificationMessage),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: controller.configureNotifications,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('알림 권한 설정'),
            ),
          ],
        ),
      ),
    );
  }
}

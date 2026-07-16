import 'package:flutter/material.dart';

import '../domain/attendance_schedule.dart';
import '../domain/training_calendar.dart';

class ScheduleEditScreen extends StatefulWidget {
  const ScheduleEditScreen({super.key, this.initialSchedule});

  final AttendanceSchedule? initialSchedule;

  @override
  State<ScheduleEditScreen> createState() => _ScheduleEditScreenState();
}

class _ScheduleEditScreenState extends State<ScheduleEditScreen> {
  late AttendanceAction _action;
  late TimeOfDay _time;
  late ScheduleRecurrence _recurrence;
  late Set<int> _weekdays;
  late DateTime _date;
  late bool _excludePublicHolidays;
  late bool _enabled;

  bool get _editing => widget.initialSchedule != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSchedule;
    _action = initial?.action ?? AttendanceAction.checkIn;
    _time = TimeOfDay(hour: initial?.hour ?? 9, minute: initial?.minute ?? 0);
    _recurrence = initial?.recurrence ?? ScheduleRecurrence.weekly;
    _weekdays =
        initial?.weekdays.toSet() ??
        {
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
        };
    _date = initial?.date ?? _defaultDate();
    _excludePublicHolidays = initial?.excludePublicHolidays ?? true;
    _enabled = initial?.enabled ?? true;
  }

  DateTime _defaultDate() {
    final today = DateTime.now();
    if (today.isBefore(TrainingCalendar.courseStart)) {
      return TrainingCalendar.courseStart;
    }
    if (today.isAfter(TrainingCalendar.courseEnd)) {
      return TrainingCalendar.courseEnd;
    }
    return DateTime(today.year, today.month, today.day);
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(context: context, initialTime: _time);
    if (selected != null && mounted) setState(() => _time = selected);
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: TrainingCalendar.courseStart,
      lastDate: TrainingCalendar.courseEnd,
      helpText: '실행 날짜 선택',
    );
    if (selected != null && mounted) setState(() => _date = selected);
  }

  void _save() {
    if (_recurrence == ScheduleRecurrence.weekly && _weekdays.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('요일을 하나 이상 선택해주세요.')));
      return;
    }
    final initial = widget.initialSchedule;
    Navigator.of(context).pop(
      AttendanceSchedule(
        id:
            initial?.id ??
            DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        action: _action,
        hour: _time.hour,
        minute: _time.minute,
        recurrence: _recurrence,
        weekdays: _recurrence == ScheduleRecurrence.weekly ? _weekdays : {},
        date: _recurrence == ScheduleRecurrence.once ? _date : null,
        excludePublicHolidays: _excludePublicHolidays,
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final holidayName = TrainingCalendar.holidayName(_date);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '일정 수정' : '일정 추가')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DropdownButtonFormField<AttendanceAction>(
            initialValue: _action,
            decoration: const InputDecoration(
              labelText: '동작',
              border: OutlineInputBorder(),
            ),
            items: AttendanceAction.values
                .map(
                  (action) => DropdownMenuItem(
                    value: action,
                    child: Text(action.label),
                  ),
                )
                .toList(),
            onChanged: (action) {
              if (action != null) setState(() => _action = action);
            },
          ),
          const SizedBox(height: 20),
          SegmentedButton<ScheduleRecurrence>(
            segments: ScheduleRecurrence.values
                .map(
                  (value) =>
                      ButtonSegment(value: value, label: Text(value.label)),
                )
                .toList(),
            selected: {_recurrence},
            onSelectionChanged: (selection) {
              setState(() => _recurrence = selection.single);
            },
          ),
          const SizedBox(height: 20),
          if (_recurrence == ScheduleRecurrence.weekly) ...[
            Text('요일', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: weekdayLabels.entries.map((entry) {
                return FilterChip(
                  label: Text(entry.value),
                  selected: _weekdays.contains(entry.key),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _weekdays.add(entry.key);
                      } else {
                        _weekdays.remove(entry.key);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('공휴일 제외'),
              subtitle: const Text('2026년 과정 기간의 법정공휴일에는 실행하지 않습니다.'),
              value: _excludePublicHolidays,
              onChanged: (value) {
                setState(() => _excludePublicHolidays = value);
              },
            ),
          ] else ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: Divider.createBorderSide(context),
              ),
              title: const Text('실행 날짜'),
              subtitle: holidayName == null ? null : Text(holidayName),
              trailing: Text(
                formatDate(_date),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: _pickDate,
            ),
            if (holidayName != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('직접 지정한 일정은 공휴일에도 실행 대상으로 유지됩니다.'),
              ),
          ],
          const SizedBox(height: 20),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: Divider.createBorderSide(context),
            ),
            title: const Text('실행 시각'),
            trailing: Text(
              '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            onTap: _pickTime,
          ),
          const SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('일정 활성화'),
            value: _enabled,
            onChanged: (enabled) => setState(() => _enabled = enabled),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('저장')),
        ],
      ),
    );
  }
}

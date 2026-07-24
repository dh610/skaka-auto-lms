import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../domain/attendance_schedule.dart';
import '../domain/alarm_settings.dart';
import '../domain/schedule_conflict.dart';
import '../domain/training_calendar.dart';
import 'schedule_visuals.dart';

class ScheduleEditScreen extends StatefulWidget {
  const ScheduleEditScreen({
    super.key,
    this.initialSchedule,
    this.initialAlarmSettings = const AlarmSettings(),
    this.onPickAlarmSound,
    this.existingSchedules = const [],
  });

  final AttendanceSchedule? initialSchedule;
  final AlarmSettings initialAlarmSettings;
  final Future<AlarmSound?> Function(AlarmSound current)? onPickAlarmSound;
  final List<AttendanceSchedule> existingSchedules;

  @override
  State<ScheduleEditScreen> createState() => _ScheduleEditScreenState();
}

class _ScheduleEditScreenState extends State<ScheduleEditScreen> {
  final _scrollController = ScrollController();
  final _scrollViewportKey = GlobalKey();
  final _inlineSaveKey = GlobalKey();
  late AttendanceAction _action;
  late TimeOfDay _time;
  late ScheduleRecurrence _recurrence;
  late Set<int> _weekdays;
  late DateTime _date;
  late bool _excludePublicHolidays;
  late bool _enabled;
  late AlarmSettings _alarmSettings;
  bool _showStickySave = true;
  bool _showInitialScrollbar = true;
  bool _visibilityUpdateScheduled = false;
  Timer? _scrollbarHintTimer;

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
    _alarmSettings = initial?.alarmSettings ?? widget.initialAlarmSettings;
    _scrollController.addListener(_scheduleStickySaveVisibilityUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateStickySaveVisibility();
    });
    _scrollbarHintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showInitialScrollbar = false);
    });
  }

  @override
  void dispose() {
    _scrollbarHintTimer?.cancel();
    _scrollController
      ..removeListener(_scheduleStickySaveVisibilityUpdate)
      ..dispose();
    super.dispose();
  }

  void _scheduleStickySaveVisibilityUpdate() {
    if (_visibilityUpdateScheduled) return;
    _visibilityUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityUpdateScheduled = false;
      _updateStickySaveVisibility();
    });
  }

  void _updateStickySaveVisibility() {
    if (!mounted) return;
    final buttonBox =
        _inlineSaveKey.currentContext?.findRenderObject() as RenderBox?;
    final viewportBox =
        _scrollViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null ||
        !buttonBox.hasSize ||
        viewportBox == null ||
        !viewportBox.hasSize) {
      return;
    }
    final buttonTop = buttonBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportBox
        .localToGlobal(Offset(0, viewportBox.size.height))
        .dy;
    final shouldShow = buttonTop >= viewportBottom;
    if (shouldShow != _showStickySave) {
      setState(() => _showStickySave = shouldShow);
    }
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
    final selected = await showModalBottomSheet<TimeOfDay>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _TimeWheelPicker(initialTime: _time),
    );
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

  Future<void> _pickAlarmSound() async {
    final selected = await widget.onPickAlarmSound?.call(_alarmSettings.sound);
    if (selected != null && mounted) {
      setState(() => _alarmSettings = _alarmSettings.copyWith(sound: selected));
    }
  }

  Future<void> _pickSnooze() async {
    final selected = await showDialog<(int, int?)>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('다시 알림'),
        children: [
          for (final minutes in const [1, 3, 5, 10, 15])
            for (final maximum in const <int?>[0, 1, 3, 5, 10, null])
              if ((minutes, maximum) ==
                  (
                    _alarmSettings.snoozeMinutes,
                    _alarmSettings.maximumSnoozeCount,
                  ))
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop((minutes, maximum)),
                  child: Text(_snoozeLabel(minutes, maximum)),
                ),
          const Divider(),
          for (final minutes in const [1, 3, 5, 10, 15])
            SimpleDialogOption(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((minutes, _alarmSettings.maximumSnoozeCount)),
              child: Text('$minutes분 간격'),
            ),
          const Divider(),
          for (final maximum in const <int?>[0, 1, 3, 5, 10, null])
            SimpleDialogOption(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((_alarmSettings.snoozeMinutes, maximum)),
              child: Text(maximum == null ? '횟수 제한 없음' : '최대 $maximum회'),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _alarmSettings = _alarmSettings.copyWith(
        snoozeMinutes: selected.$1,
        maximumSnoozeCount: selected.$2,
        clearMaximumSnoozeCount: selected.$2 == null,
      );
    });
  }

  void _showExcludedHolidays() {
    final holidays = TrainingCalendar.holidaysForWeekdays(_weekdays);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('제외되는 공휴일', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '${formatWeekdays(_weekdays)} 일정과 겹치는 공휴일입니다'
                '(2026.07.14~2026.12.18 기준)',
              ),
              const SizedBox(height: 12),
              if (holidays.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('선택한 요일과 겹치는 공휴일이 없습니다.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: holidays.length,
                    itemBuilder: (context, index) {
                      final holiday = holidays[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_busy_outlined),
                        title: Text(holiday.name),
                        subtitle: Text(
                          '${formatDate(holiday.date)} (${weekdayLabels[holiday.date.weekday]})',
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (_recurrence == ScheduleRecurrence.weekly && _weekdays.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('요일을 하나 이상 선택해주세요.')));
      return;
    }
    final initial = widget.initialSchedule;
    final schedule = AttendanceSchedule(
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
      alarmSettings: _alarmSettings,
    );
    final conflict = findScheduleConflict(schedule, widget.existingSchedules);
    if (conflict != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(conflict.message)));
      return;
    }
    Navigator.of(context).pop(schedule);
  }

  @override
  Widget build(BuildContext context) {
    final holidayName = TrainingCalendar.holidayName(_date);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '일정 수정' : '일정 추가')),
      body: Scrollbar(
        controller: _scrollController,
        thumbVisibility: _showInitialScrollbar ? true : null,
        child: ListView(
          key: _scrollViewportKey,
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            32 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            _SectionTitle(
              title: '출결 동작',
              description: '알림을 눌러 인증한 뒤 처리할 동작을 선택하세요.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AttendanceAction.values.map((action) {
                return ChoiceChip(
                  avatar: Icon(action.icon, size: 18),
                  label: Text(action.label),
                  selected: _action == action,
                  onSelected: (_) => setState(() => _action = action),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            const _SectionTitle(
              title: '실행 시각',
              description: '선택한 시각에 출결 인증 알림을 표시합니다.',
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('알림 시각'),
                trailing: Text(
                  formatDisplayTime(_time.hour, _time.minute),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                onTap: _pickTime,
              ),
            ),
            const SizedBox(height: 28),
            const _SectionTitle(
              title: '반복 방식',
              description: '요일을 반복하거나 과정 기간 내 날짜를 직접 지정할 수 있습니다.',
            ),
            const SizedBox(height: 12),
            SegmentedButton<ScheduleRecurrence>(
              expandedInsets: EdgeInsets.zero,
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '실행 요일',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
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
                      const Divider(height: 28),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('공휴일 제외'),
                        subtitle: const Text('2026년 과정 기간의 법정공휴일에는 실행하지 않습니다.'),
                        value: _excludePublicHolidays,
                        onChanged: (value) {
                          setState(() => _excludePublicHolidays = value);
                        },
                      ),
                      TextButton.icon(
                        onPressed: _weekdays.isEmpty
                            ? null
                            : _showExcludedHolidays,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('제외되는 공휴일 보기'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('실행 날짜'),
                  subtitle: holidayName == null ? null : Text(holidayName),
                  trailing: Text(
                    formatDate(_date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: _pickDate,
                ),
              ),
              if (holidayName != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('직접 지정한 일정은 공휴일에도 실행 대상으로 유지됩니다.'),
                ),
            ],
            const SizedBox(height: 24),
            const _SectionTitle(
              title: '알람 설정',
              description: '알람이 울릴 때 사용할 소리와 동작을 설정합니다.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.music_note_outlined),
                    title: const Text('알람음'),
                    subtitle: Text(_alarmSettings.sound.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.onPickAlarmSound == null
                        ? null
                        : _pickAlarmSound,
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        const Expanded(child: Text('음량')),
                        Text('${_alarmSettings.volumePercent}%'),
                      ],
                    ),
                  ),
                  Slider(
                    value: _alarmSettings.volumePercent.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${_alarmSettings.volumePercent}%',
                    onChanged: (value) => setState(() {
                      _alarmSettings = _alarmSettings.copyWith(
                        volumePercent: value.round(),
                      );
                    }),
                  ),
                  SwitchListTile(
                    title: const Text('진동'),
                    value: _alarmSettings.vibrationEnabled,
                    onChanged: (value) => setState(() {
                      _alarmSettings = _alarmSettings.copyWith(
                        vibrationEnabled: value,
                      );
                    }),
                  ),
                  SwitchListTile(
                    title: const Text('점점 크게'),
                    subtitle: const Text('처음 30초 동안 설정 음량까지 높입니다.'),
                    value: _alarmSettings.gradualVolumeEnabled,
                    onChanged: (value) => setState(() {
                      _alarmSettings = _alarmSettings.copyWith(
                        gradualVolumeEnabled: value,
                      );
                    }),
                  ),
                  ListTile(
                    title: const Text('다시 알림'),
                    subtitle: Text(
                      _snoozeLabel(
                        _alarmSettings.snoozeMinutes,
                        _alarmSettings.maximumSnoozeCount,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickSnooze,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('일정 활성화'),
              subtitle: const Text('끄면 일정은 보관되지만 알림을 예약하지 않습니다.'),
              value: _enabled,
              onChanged: (enabled) => setState(() => _enabled = enabled),
            ),
            const SizedBox(height: 20),
            KeyedSubtree(
              key: const Key('inline-save-button'),
              child: FilledButton(
                key: _inlineSaveKey,
                onPressed: _save,
                child: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _showStickySave
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  key: const Key('sticky-save-button'),
                  onPressed: _save,
                  child: const Text('저장'),
                ),
              ),
            )
          : null,
    );
  }
}

String _snoozeLabel(int minutes, int? maximum) =>
    '$minutes분 · ${maximum == null ? '제한 없음' : '최대 $maximum회'}';

class _TimeWheelPicker extends StatefulWidget {
  const _TimeWheelPicker({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_TimeWheelPicker> createState() => _TimeWheelPickerState();
}

class _TimeWheelPickerState extends State<_TimeWheelPicker>
    with WidgetsBindingObserver {
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _periodController;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  final _inputFormKey = GlobalKey<FormState>();
  late final TextEditingController _hourTextController;
  late final TextEditingController _minuteTextController;
  late final FocusNode _hourFocusNode;
  late final FocusNode _minuteFocusNode;
  bool _editingWithKeyboard = false;
  bool _keyboardWasVisible = false;
  Offset? _hourPointerDown;
  Offset? _minutePointerDown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hour = widget.initialTime.hour;
    _minute = widget.initialTime.minute;
    _periodController = FixedExtentScrollController(initialItem: _hour ~/ 12);
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
    _hourTextController = TextEditingController();
    _minuteTextController = TextEditingController();
    _hourFocusNode = FocusNode();
    _minuteFocusNode = FocusNode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _hourTextController.dispose();
    _minuteTextController.dispose();
    _hourFocusNode.dispose();
    _minuteFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!mounted || !_editingWithKeyboard) return;
    final keyboardVisible = View.of(context).viewInsets.bottom > 0;
    if (keyboardVisible) {
      _keyboardWasVisible = true;
    } else if (_keyboardWasVisible) {
      _keyboardWasVisible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editingWithKeyboard) {
          _applyKeyboardInput(validate: false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: 430,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '실행 시각 선택',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '위아래로 밀어 선택하거나 숫자를 눌러 직접 입력하세요.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildWheelPicker(context, textStyle)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('선택'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWheelPicker(BuildContext context, TextStyle? textStyle) {
    return Form(
      key: _inputFormKey,
      child: Row(
        children: [
          Expanded(
            child: CupertinoPicker(
              scrollController: _periodController,
              itemExtent: 52,
              useMagnifier: true,
              magnification: 1.1,
              onSelectedItemChanged: _selectPeriod,
              children: const [
                Center(child: Text('오전')),
                Center(child: Text('오후')),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _editingWithKeyboard
                ? TextFormField(
                    key: const Key('hour-input'),
                    controller: _hourTextController,
                    focusNode: _hourFocusNode,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    textAlign: TextAlign.center,
                    style: textStyle,
                    decoration: const InputDecoration(hintText: '시'),
                    validator: _validateHour,
                    onFieldSubmitted: (_) => _minuteFocusNode.requestFocus(),
                  )
                : Listener(
                    key: const Key('hour-wheel'),
                    onPointerDown: (event) => _hourPointerDown = event.position,
                    onPointerUp: (event) {
                      if (_isTap(_hourPointerDown, event.position)) {
                        _showNumberInput(focusHour: true);
                      }
                      _hourPointerDown = null;
                    },
                    onPointerCancel: (_) => _hourPointerDown = null,
                    child: CupertinoPicker(
                      scrollController: _hourController,
                      itemExtent: 52,
                      useMagnifier: true,
                      magnification: 1.12,
                      looping: true,
                      onSelectedItemChanged: _selectHour,
                      children: List.generate(
                        24,
                        (hour) => Center(
                          child: Text(
                            '${_hourOfPeriod(hour)}',
                            style: textStyle,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          Text('시', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Expanded(
            child: _editingWithKeyboard
                ? TextFormField(
                    key: const Key('minute-input'),
                    controller: _minuteTextController,
                    focusNode: _minuteFocusNode,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    style: textStyle,
                    decoration: const InputDecoration(hintText: '분'),
                    validator: _validateMinute,
                    onFieldSubmitted: (_) => _applyKeyboardInput(),
                  )
                : Listener(
                    key: const Key('minute-wheel'),
                    onPointerDown: (event) =>
                        _minutePointerDown = event.position,
                    onPointerUp: (event) {
                      if (_isTap(_minutePointerDown, event.position)) {
                        _showNumberInput(focusHour: false);
                      }
                      _minutePointerDown = null;
                    },
                    onPointerCancel: (_) => _minutePointerDown = null,
                    child: CupertinoPicker(
                      scrollController: _minuteController,
                      itemExtent: 52,
                      useMagnifier: true,
                      magnification: 1.12,
                      looping: true,
                      onSelectedItemChanged: (value) => _minute = value,
                      children: List.generate(
                        60,
                        (minute) => Center(
                          child: Text(
                            minute.toString().padLeft(2, '0'),
                            style: textStyle,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          Text('분', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  void _selectPeriod(int value) {
    final nextHour = (_hour % 12) + (value * 12);
    if (nextHour == _hour) return;
    setState(() => _hour = nextHour);
    _hourController.animateToItem(
      nextHour,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _selectHour(int value) {
    if (_hour == value) return;
    final previousPeriod = _hour ~/ 12;
    setState(() => _hour = value);
    final nextPeriod = value ~/ 12;
    if (previousPeriod != nextPeriod) {
      _periodController.animateToItem(
        nextPeriod,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _showNumberInput({required bool focusHour}) {
    _hourTextController.text = '${_hourOfPeriod(_hour)}';
    _minuteTextController.text = _minute.toString().padLeft(2, '0');
    _keyboardWasVisible = false;
    setState(() => _editingWithKeyboard = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusNode = focusHour ? _hourFocusNode : _minuteFocusNode;
      focusNode.requestFocus();
      final controller = focusHour
          ? _hourTextController
          : _minuteTextController;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
  }

  bool _applyKeyboardInput({bool validate = true}) {
    if (!_editingWithKeyboard) return true;
    if (validate && !_inputFormKey.currentState!.validate()) return false;
    final enteredHour = int.tryParse(_hourTextController.text);
    final enteredMinute = int.tryParse(_minuteTextController.text);
    final validInput =
        enteredHour != null &&
        enteredHour >= 1 &&
        enteredHour <= 12 &&
        enteredMinute != null &&
        enteredMinute >= 0 &&
        enteredMinute <= 59;
    if (validate && !validInput) return false;
    final period = _hour ~/ 12;
    final nextHour = validInput ? (enteredHour % 12) + (period * 12) : _hour;
    setState(() {
      _hour = nextHour;
      if (validInput) _minute = enteredMinute;
      _editingWithKeyboard = false;
    });
    FocusScope.of(context).unfocus();
    _syncWheelPositionsAfterBuild();
    return true;
  }

  void _syncWheelPositionsAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingWithKeyboard) return;
      if (_hourController.hasClients) {
        _hourController.jumpToItem(_hour);
      }
      if (_minuteController.hasClients) {
        _minuteController.jumpToItem(_minute);
      }
    });
  }

  static String? _validateHour(String? value) {
    final hour = int.tryParse(value ?? '');
    return hour == null || hour < 1 || hour > 12 ? '1~12 입력' : null;
  }

  static String? _validateMinute(String? value) {
    final minute = int.tryParse(value ?? '');
    return minute == null || minute < 0 || minute > 59 ? '0~59 입력' : null;
  }

  bool _isTap(Offset? start, Offset end) {
    return start != null && (end - start).distance < 8;
  }

  int _hourOfPeriod(int hour) => hour % 12 == 0 ? 12 : hour % 12;

  void _submit() {
    if (!_applyKeyboardInput()) return;
    Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: _minute));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../features/attendance/data/callback_link_settings.dart';
import '../features/schedule/application/notification_scheduler.dart';

class InitialSetupScreen extends StatefulWidget {
  InitialSetupScreen({
    super.key,
    required this.notificationScheduler,
    required this.callbackLinkSettings,
    required this.onFinished,
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  final NotificationScheduler notificationScheduler;
  final CallbackLinkSettings callbackLinkSettings;
  final Future<void> Function() onFinished;
  final bool isAndroid;

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _working = false;
  bool _notificationReady = false;
  bool _callbackLinkReady = false;
  bool _waitingForLinkSettings = false;
  bool _linkSetupIncomplete = false;

  bool get _allReady =>
      _notificationReady && (!widget.isAndroid || _callbackLinkReady);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForLinkSettings) {
      unawaited(_handleLinkSettingsReturn());
    }
  }

  Future<void> _refresh() async {
    final notificationReady = await widget.notificationScheduler
        .arePermissionsGranted();
    final callbackLinkReady =
        !widget.isAndroid || await widget.callbackLinkSettings.isEnabled();
    if (!mounted) return;
    setState(() {
      _notificationReady = notificationReady;
      _callbackLinkReady = callbackLinkReady;
      _loading = false;
    });
    if (_allReady) await widget.onFinished();
  }

  Future<void> _continueSetup() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (!_notificationReady) {
        await widget.notificationScheduler.requestPermissions();
        _notificationReady = await widget.notificationScheduler
            .arePermissionsGranted();
        if (mounted) setState(() {});
      }
      if (widget.isAndroid && !_callbackLinkReady) {
        if (mounted) setState(() => _working = false);
        await _configureCallbackLink();
        return;
      }
      if (_allReady) await widget.onFinished();
    } finally {
      if (mounted && !_waitingForLinkSettings) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _configureNotifications() async {
    if (_working || _notificationReady) return;
    setState(() => _working = true);
    try {
      await widget.notificationScheduler.requestPermissions();
      final ready = await widget.notificationScheduler.arePermissionsGranted();
      if (!mounted) return;
      setState(() => _notificationReady = ready);
      if (_allReady) await widget.onFinished();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _configureCallbackLink() async {
    if (_working || _callbackLinkReady) return;
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => const _CallbackLinkGuideDialog(),
    );
    if (shouldOpen != true || !mounted) return;
    setState(() {
      _working = true;
      _waitingForLinkSettings = true;
      _linkSetupIncomplete = false;
    });
    try {
      await widget.callbackLinkSettings.open();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _waitingForLinkSettings = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Android 링크 설정 화면을 열지 못했습니다.')),
      );
    }
  }

  Future<void> _handleLinkSettingsReturn() async {
    final enabled = await widget.callbackLinkSettings.isEnabled();
    if (!mounted) return;
    _waitingForLinkSettings = false;
    setState(() {
      _callbackLinkReady = enabled;
      _linkSetupIncomplete = !enabled;
      _working = false;
    });
    if (_allReady) {
      await widget.onFinished();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '설정이 아직 완료되지 않았습니다. 지원되는 웹 주소에서 '
            'att.skala-ai.com까지 켜주세요.',
          ),
        ),
      );
    }
  }

  Future<void> _skip() async {
    if (_working) return;
    setState(() => _working = true);
    await widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('초기 설정')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    '앱 사용 준비를 마쳐주세요',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '일정 알림을 받고 Google 인증 후 앱으로 돌아오기 위해 '
                    '필요한 설정입니다.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SetupItem(
                    icon: Icons.notifications_active_outlined,
                    title: '일정 알림',
                    description: '등록한 출결 일정에 맞춰 알림을 표시합니다.',
                    ready: _notificationReady,
                    actionLabel: '설정하기',
                    onTap: _configureNotifications,
                  ),
                  if (widget.isAndroid) ...[
                    const SizedBox(height: 12),
                    _SetupItem(
                      icon: Icons.add_link_rounded,
                      title: '인증 후 앱 복귀',
                      description: 'Google 인증 완료 후 이 앱으로 자동 복귀합니다.',
                      ready: _callbackLinkReady,
                      actionLabel: '설정 방법',
                      onTap: _configureCallbackLink,
                    ),
                    if (_linkSetupIncomplete) ...[
                      const SizedBox(height: 6),
                      Text(
                        '지원되는 웹 주소에서 att.skala-ai.com까지 켜야 완료됩니다.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _working ? null : _continueSetup,
                    child: Text(
                      _working
                          ? '설정 확인 중…'
                          : _allReady
                          ? '설정 완료'
                          : '필요한 설정 계속하기',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _working ? null : _skip,
                    child: const Text('나중에 설정'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '나중에 설정해도 일정 관리와 Google 인증을 시작할 때 '
                    '필요한 권한을 다시 안내합니다.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SetupItem extends StatelessWidget {
  const _SetupItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.ready,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool ready;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: ready ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(description),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!ready)
                            TextButton(
                              onPressed: onTap,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(actionLabel),
                            ),
                          if (!ready) const SizedBox(height: 4),
                          Chip(
                            avatar: Icon(
                              ready
                                  ? Icons.check_circle_rounded
                                  : Icons.info_outline_rounded,
                              size: 18,
                            ),
                            label: Text(ready ? '완료' : '설정 필요'),
                            backgroundColor: ready
                                ? colors.primaryContainer
                                : colors.secondaryContainer,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallbackLinkGuideDialog extends StatelessWidget {
  const _CallbackLinkGuideDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('인증 후 앱 복귀 설정'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Android 설정 화면에서 아래 항목을 모두 허용해 주세요.'),
            SizedBox(height: 18),
            _GuideStep(
              number: 1,
              title: '지원되는 링크 열기',
              description: '오른쪽 스위치를 켜세요.',
            ),
            SizedBox(height: 14),
            _GuideStep(
              number: 2,
              title: '지원되는 웹 주소',
              description: '항목을 눌러 상세 화면으로 들어가세요.',
            ),
            SizedBox(height: 14),
            _GuideStep(
              number: 3,
              title: 'att.skala-ai.com',
              description: '오른쪽 스위치를 켠 뒤 앱으로 돌아오세요.',
            ),
            SizedBox(height: 18),
            Text(
              '기기와 Android 버전에 따라 메뉴 배치가 조금 다를 수 있습니다.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('설정 화면 열기'),
        ),
      ],
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final int number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          child: Text('$number', style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(description),
            ],
          ),
        ),
      ],
    );
  }
}

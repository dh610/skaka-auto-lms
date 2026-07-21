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
        _waitingForLinkSettings = true;
        await widget.callbackLinkSettings.open();
        return;
      }
      if (_allReady) await widget.onFinished();
    } finally {
      if (mounted && !_waitingForLinkSettings) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _handleLinkSettingsReturn() async {
    final enabled = await widget.callbackLinkSettings.isEnabled();
    if (!mounted) return;
    _waitingForLinkSettings = false;
    setState(() {
      _callbackLinkReady = enabled;
      _working = false;
    });
    if (_allReady) await widget.onFinished();
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
                  ),
                  if (widget.isAndroid) ...[
                    const SizedBox(height: 12),
                    _SetupItem(
                      icon: Icons.add_link_rounded,
                      title: '인증 후 앱 복귀',
                      description: 'Google 인증 완료 후 이 앱으로 자동 복귀합니다.',
                      ready: _callbackLinkReady,
                    ),
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
  });

  final IconData icon;
  final String title;
  final String description;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(description),
        trailing: Chip(
          avatar: Icon(
            ready ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 18,
          ),
          label: Text(ready ? '완료' : '설정 필요'),
          backgroundColor: ready
              ? colors.primaryContainer
              : colors.secondaryContainer,
        ),
      ),
    );
  }
}

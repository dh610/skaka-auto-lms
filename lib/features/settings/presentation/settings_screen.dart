import 'dart:async';

import 'package:flutter/material.dart';

import '../../attendance/data/callback_link_settings.dart';
import '../../profile/domain/user_profile.dart';
import '../../schedule/application/notification_scheduler.dart';
import '../application/settings_controller.dart';
import '../domain/app_version.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.profile,
    required this.themeMode,
    required this.isAndroid,
    required this.notificationSettings,
    this.fullScreenAlarmSettings,
    required this.callbackLinkSettings,
    required this.appVersionProvider,
    required this.onEditProfile,
    required this.onThemeModeChanged,
    Future<void> Function(ThemeMode)? persistThemeMode,
  }) : persistThemeMode = persistThemeMode ?? _noOpThemePersistence;

  final UserProfile profile;
  final ThemeMode themeMode;
  final bool isAndroid;
  final NotificationPermissionSettings notificationSettings;
  final FullScreenAlarmPermissionSettings? fullScreenAlarmSettings;
  final CallbackLinkSettings callbackLinkSettings;
  final AppVersionProvider appVersionProvider;
  final Future<UserProfile?> Function() onEditProfile;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final Future<void> Function(ThemeMode) persistThemeMode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final SettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SettingsController(
      initialProfile: widget.profile,
      initialThemeMode: widget.themeMode,
      isAndroid: widget.isAndroid,
      notificationSettings: widget.notificationSettings,
      fullScreenAlarmSettings: widget.fullScreenAlarmSettings,
      callbackLinkSettings: widget.callbackLinkSettings,
      appVersionProvider: widget.appVersionProvider,
      editProfile: widget.onEditProfile,
      applyThemeMode: widget.onThemeModeChanged,
      persistThemeMode: widget.persistThemeMode,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_controller.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runOperation(Future<String?> Function() operation) async {
    final message = await operation();
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showThemePicker() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('테마 선택'),
        children: ThemeMode.values.map((mode) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(mode),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_themeIcon(mode)),
              title: Text(_themeLabel(mode)),
              trailing: _controller.themeMode == mode
                  ? const Icon(Icons.check)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
    if (selected != null) {
      await _runOperation(() => _controller.selectTheme(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('설정')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _SectionTitle('사용자 정보'),
            ListTile(
              title: Text(_controller.profile.name),
              subtitle: Text(
                '${_controller.profile.region.label} · '
                '${_controller.profile.classLabel}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('사용자 정보 변경'),
              trailing: _controller.profileEditInProgress
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _controller.profileEditInProgress
                  ? null
                  : () => _runOperation(_controller.editProfile),
            ),
            const Divider(),
            const _SectionTitle('화면 설정'),
            ListTile(
              leading: Icon(_themeIcon(_controller.themeMode)),
              title: const Text('테마'),
              subtitle: Text(_themeLabel(_controller.themeMode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showThemePicker,
            ),
            const Divider(),
            const _SectionTitle('권한 및 필수 설정'),
            _PermissionListTile(
              label: '알림 권한',
              status: _controller.notificationStatus,
              onTap: () => _runOperation(_controller.openNotificationSettings),
            ),
            if (widget.isAndroid)
              _PermissionListTile(
                label: '정확한 알람 권한',
                status: _controller.exactAlarmStatus,
                onTap: () => _runOperation(_controller.openExactAlarmSettings),
              ),
            if (widget.isAndroid && widget.fullScreenAlarmSettings != null)
              _PermissionListTile(
                label: '전체 화면 알람 권한',
                status: _controller.fullScreenAlarmStatus,
                onTap: () =>
                    _runOperation(_controller.openFullScreenAlarmSettings),
              ),
            if (widget.isAndroid)
              _PermissionListTile(
                label: '인증 후 앱 복귀 설정',
                status: _controller.callbackLinkStatus,
                onTap: () =>
                    _runOperation(_controller.openCallbackLinkSettings),
              ),
            const Divider(),
            const _SectionTitle('앱 정보'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('버전'),
              subtitle: Text(_versionLabel(_controller)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _noOpThemePersistence(ThemeMode _) async {}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PermissionListTile extends StatelessWidget {
  const _PermissionListTile({
    required this.label,
    required this.status,
    required this.onTap,
  });

  final String label;
  final SettingsPermissionStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListTile(
        title: Text(label),
        subtitle: _PermissionStatusIndicator(status),
        trailing: const Icon(Icons.open_in_new),
        onTap: onTap,
      ),
    );
  }
}

class _PermissionStatusIndicator extends StatelessWidget {
  const _PermissionStatusIndicator(this.status);

  final SettingsPermissionStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (status) {
      SettingsPermissionStatus.loading => (null, '확인 중'),
      SettingsPermissionStatus.allowed => (Icons.check_circle_outline, '허용됨'),
      SettingsPermissionStatus.needed => (Icons.warning_amber_rounded, '설정 필요'),
      SettingsPermissionStatus.unavailable => (Icons.help_outline, '확인할 수 없음'),
    };
    final color = switch (status) {
      SettingsPermissionStatus.allowed => Theme.of(context).colorScheme.primary,
      SettingsPermissionStatus.needed => Theme.of(context).colorScheme.error,
      SettingsPermissionStatus.loading ||
      SettingsPermissionStatus.unavailable => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

String _themeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '시스템 설정',
  ThemeMode.light => '라이트',
  ThemeMode.dark => '다크',
};

IconData _themeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.settings_suggest_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};

String _versionLabel(SettingsController controller) {
  return switch (controller.versionStatus) {
    SettingsVersionStatus.loading => '버전 정보 확인 중',
    SettingsVersionStatus.available =>
      '버전 ${controller.appVersion!.version} '
          '(빌드 ${controller.appVersion!.buildNumber})',
    SettingsVersionStatus.unavailable => '버전 정보를 확인할 수 없음',
  };
}

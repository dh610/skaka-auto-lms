import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../features/attendance/data/attendance_gateway.dart';
import '../features/attendance/presentation/attendance_screen.dart';
import '../features/attendance/data/callback_link_settings.dart';
import '../features/profile/data/profile_store.dart';
import '../features/profile/data/skala_profile_verifier.dart';
import '../features/profile/domain/profile_verifier.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/profile/presentation/profile_setup_screen.dart';
import '../features/schedule/application/schedule_controller.dart';
import '../features/schedule/application/notification_scheduler.dart';
import '../features/schedule/data/schedule_store.dart';
import '../features/schedule/data/local_notification_scheduler.dart';
import '../features/settings/data/package_info_app_version_provider.dart';
import '../features/settings/domain/app_version.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'app_theme.dart';
import 'initial_setup_screen.dart';
import 'initial_setup_store.dart';
import 'theme_mode_store.dart';

class SkalaAttendanceApp extends StatefulWidget {
  SkalaAttendanceApp({
    super.key,
    this.notificationScheduler,
    this.notificationPermissionSettings,
    this.callbackLinkSettings,
    this.appVersionProvider,
    this.attendanceGatewayFactory,
    this.themeModeStore,
    this.initialSetupStore,
    this.profileVerifier,
    bool? isAndroid,
  }) : isAndroid = isAndroid ?? Platform.isAndroid;

  final NotificationScheduler? notificationScheduler;
  final NotificationPermissionSettings? notificationPermissionSettings;
  final CallbackLinkSettings? callbackLinkSettings;
  final AppVersionProvider? appVersionProvider;
  final AttendanceGateway Function()? attendanceGatewayFactory;
  final ThemeModeStore? themeModeStore;
  final InitialSetupStore? initialSetupStore;
  final ProfileVerifier? profileVerifier;
  final bool isAndroid;

  @override
  State<SkalaAttendanceApp> createState() => _SkalaAttendanceAppState();
}

class _SkalaAttendanceAppState extends State<SkalaAttendanceApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _profileStore = ProfileStore();
  late final ThemeModeStore _themeModeStore;
  late final InitialSetupStore _initialSetupStore;
  late final NotificationScheduler _notificationScheduler;
  late final NotificationPermissionSettings _notificationPermissionSettings;
  late final CallbackLinkSettings _callbackLinkSettings;
  late final AppVersionProvider _appVersionProvider;
  late final ScheduleController _scheduleController;
  late final Future<void> _scheduleInitialization;
  late final ProfileVerifier _profileVerifier;
  UserProfile? _profile;
  bool _loading = true;
  bool _initialSetupCompleted = false;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeModeStore = widget.themeModeStore ?? ThemeModeStore();
    _notificationScheduler =
        widget.notificationScheduler ?? LocalNotificationScheduler();
    _notificationPermissionSettings =
        widget.notificationPermissionSettings ??
        switch (_notificationScheduler) {
          final NotificationPermissionSettings settings => settings,
          _ => _UnavailableNotificationPermissionSettings(
            isAndroid: widget.isAndroid,
          ),
        };
    _callbackLinkSettings =
        widget.callbackLinkSettings ?? PlatformCallbackLinkSettings();
    _appVersionProvider =
        widget.appVersionProvider ?? PackageInfoAppVersionProvider();
    _initialSetupStore = widget.initialSetupStore ?? InitialSetupStore();
    _profileVerifier = widget.profileVerifier ?? SkalaProfileVerifier();
    _scheduleController = ScheduleController(
      ScheduleStore(),
      _notificationScheduler,
    );
    _scheduleInitialization = _scheduleController.load();
    _loadProfile();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final themeMode = await _themeModeStore.load();
    if (mounted) setState(() => _themeMode = themeMode);
  }

  void _applyThemeMode(ThemeMode themeMode) {
    if (_themeMode == themeMode) return;
    setState(() => _themeMode = themeMode);
  }

  Future<void> _persistThemeMode(ThemeMode themeMode) =>
      _themeModeStore.save(themeMode);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduleController.dispose();
    _profileVerifier.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recheckInitialSetupRequirements());
    }
  }

  Future<void> _loadProfile() async {
    final profile = await _profileStore.load();
    final initialSetupCompleted = await _initialSetupStore.isCompleted();
    final requirementsReady = profile != null && initialSetupCompleted
        ? await _areInitialSetupRequirementsReady()
        : false;
    if (profile != null && initialSetupCompleted && !requirementsReady) {
      await _initialSetupStore.markIncomplete();
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _initialSetupCompleted = initialSetupCompleted && requirementsReady;
      _loading = false;
    });
  }

  Future<bool> _areInitialSetupRequirementsReady() async {
    try {
      final notificationsReady = await _notificationScheduler
          .arePermissionsGranted();
      final callbackLinkReady =
          !widget.isAndroid || await _callbackLinkSettings.isEnabled();
      return notificationsReady && callbackLinkReady;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recheckInitialSetupRequirements() async {
    if (_loading || _profile == null || !_initialSetupCompleted) {
      return;
    }
    final ready = await _areInitialSetupRequirementsReady();
    if (mounted && !ready && _initialSetupCompleted) {
      await _initialSetupStore.markIncomplete();
      if (!mounted) return;
      setState(() => _initialSetupCompleted = false);
    }
  }

  Future<void> _saveInitialProfile(UserProfile profile) async {
    await _profileStore.save(profile);
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _verifyProfile(UserProfile profile) =>
      _profileVerifier.verify(profile);

  Future<bool> _finishInitialSetup() async {
    await _scheduleInitialization;
    final synchronized = await _scheduleController.resyncNotifications();
    await _scheduleController.refreshNotificationStatus();
    if (!synchronized) return false;
    await _initialSetupStore.markCompleted();
    if (mounted) setState(() => _initialSetupCompleted = true);
    return true;
  }

  Future<UserProfile?> _editProfile() async {
    final current = _profile;
    final navigator = _navigatorKey.currentState;
    if (current == null || navigator == null) return null;
    final updated = await navigator.push<UserProfile>(
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          initialProfile: current,
          onVerify: _verifyProfile,
        ),
      ),
    );
    if (updated == null) return null;
    await _profileStore.save(updated);
    if (mounted) setState(() => _profile = updated);
    return updated;
  }

  Future<void> _openSettings() async {
    final current = _profile;
    final navigator = _navigatorKey.currentState;
    if (current == null || navigator == null) return;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          profile: current,
          themeMode: _themeMode,
          isAndroid: widget.isAndroid,
          notificationSettings: _notificationPermissionSettings,
          callbackLinkSettings: _callbackLinkSettings,
          appVersionProvider: _appVersionProvider,
          onEditProfile: _editProfile,
          onThemeModeChanged: _applyThemeMode,
          persistThemeMode: _persistThemeMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'SKALA 출결 도우미',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _profile == null
          ? ProfileSetupScreen(
              onInitialSave: _saveInitialProfile,
              onVerify: _verifyProfile,
            )
          : !_initialSetupCompleted
          ? InitialSetupScreen(
              notificationScheduler: _notificationScheduler,
              callbackLinkSettings: _callbackLinkSettings,
              onFinished: _finishInitialSetup,
              isAndroid: widget.isAndroid,
            )
          : AttendanceScreen(
              profile: _profile!,
              scheduleController: _scheduleController,
              notificationScheduler: _notificationScheduler,
              onOpenSettings: _openSettings,
              gatewayFactory: widget.attendanceGatewayFactory,
              callbackLinkSettings: _callbackLinkSettings,
              isAndroid: widget.isAndroid,
            ),
    );
  }
}

class _UnavailableNotificationPermissionSettings
    implements NotificationPermissionSettings {
  const _UnavailableNotificationPermissionSettings({required this.isAndroid});

  final bool isAndroid;

  @override
  Future<NotificationPermissionStatus> getPermissionStatus() async => isAndroid
      ? const NotificationPermissionStatus.android(
          notificationsAllowed: null,
          exactAlarmsAllowed: null,
        )
      : const NotificationPermissionStatus.notApplicable(
          notificationsAllowed: null,
        );

  @override
  Future<void> openExactAlarmSettings() async {
    throw UnsupportedError('정확한 알람 설정을 열 수 없습니다.');
  }

  @override
  Future<void> openNotificationSettings() async {
    throw UnsupportedError('알림 설정을 열 수 없습니다.');
  }
}

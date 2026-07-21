import 'dart:async';

import 'package:flutter/material.dart';

import '../features/attendance/presentation/attendance_screen.dart';
import '../features/attendance/data/callback_link_settings.dart';
import '../features/profile/data/profile_store.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/profile/presentation/profile_setup_screen.dart';
import '../features/schedule/application/schedule_controller.dart';
import '../features/schedule/application/notification_scheduler.dart';
import '../features/schedule/data/schedule_store.dart';
import '../features/schedule/data/local_notification_scheduler.dart';
import 'app_theme.dart';
import 'initial_setup_screen.dart';
import 'initial_setup_store.dart';
import 'theme_mode_store.dart';

class SkalaAttendanceApp extends StatefulWidget {
  const SkalaAttendanceApp({
    super.key,
    this.notificationScheduler,
    this.callbackLinkSettings,
    this.initialSetupStore,
  });

  final NotificationScheduler? notificationScheduler;
  final CallbackLinkSettings? callbackLinkSettings;
  final InitialSetupStore? initialSetupStore;

  @override
  State<SkalaAttendanceApp> createState() => _SkalaAttendanceAppState();
}

class _SkalaAttendanceAppState extends State<SkalaAttendanceApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _profileStore = ProfileStore();
  final _themeModeStore = ThemeModeStore();
  late final InitialSetupStore _initialSetupStore;
  late final NotificationScheduler _notificationScheduler;
  late final CallbackLinkSettings _callbackLinkSettings;
  late final ScheduleController _scheduleController;
  UserProfile? _profile;
  bool _loading = true;
  bool _initialSetupCompleted = false;
  ThemeMode _themeMode = ThemeMode.system;
  bool _checkingSetupRequirements = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationScheduler =
        widget.notificationScheduler ?? LocalNotificationScheduler();
    _callbackLinkSettings =
        widget.callbackLinkSettings ?? PlatformCallbackLinkSettings();
    _initialSetupStore = widget.initialSetupStore ?? InitialSetupStore();
    _scheduleController = ScheduleController(
      ScheduleStore(),
      _notificationScheduler,
    );
    _loadProfile();
    _loadThemeMode();
    _initializeSchedules();
  }

  Future<void> _loadThemeMode() async {
    final themeMode = await _themeModeStore.load();
    if (mounted) setState(() => _themeMode = themeMode);
  }

  Future<void> _changeThemeMode(ThemeMode themeMode) async {
    if (_themeMode == themeMode) return;
    setState(() => _themeMode = themeMode);
    await _themeModeStore.save(themeMode);
  }

  Future<void> _initializeSchedules() async {
    await _scheduleController.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduleController.dispose();
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
      final callbackLinkReady = await _callbackLinkSettings.isEnabled();
      return notificationsReady && callbackLinkReady;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recheckInitialSetupRequirements() async {
    if (_checkingSetupRequirements ||
        _loading ||
        _profile == null ||
        !_initialSetupCompleted) {
      return;
    }
    _checkingSetupRequirements = true;
    try {
      final ready = await _areInitialSetupRequirementsReady();
      if (mounted && !ready) {
        setState(() => _initialSetupCompleted = false);
      }
    } finally {
      _checkingSetupRequirements = false;
    }
  }

  Future<void> _saveInitialProfile(UserProfile profile) async {
    await _profileStore.save(profile);
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _finishInitialSetup() async {
    await _initialSetupStore.markCompleted();
    await _scheduleController.refreshNotificationStatus();
    if (mounted) setState(() => _initialSetupCompleted = true);
  }

  Future<void> _editProfile() async {
    final current = _profile;
    final navigator = _navigatorKey.currentState;
    if (current == null || navigator == null) return;
    final updated = await navigator.push<UserProfile>(
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(initialProfile: current),
      ),
    );
    if (updated == null) return;
    await _profileStore.save(updated);
    if (mounted) setState(() => _profile = updated);
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
          ? ProfileSetupScreen(onInitialSave: _saveInitialProfile)
          : !_initialSetupCompleted
          ? InitialSetupScreen(
              notificationScheduler: _notificationScheduler,
              callbackLinkSettings: _callbackLinkSettings,
              onFinished: _finishInitialSetup,
            )
          : AttendanceScreen(
              profile: _profile!,
              scheduleController: _scheduleController,
              notificationScheduler: _notificationScheduler,
              onEditProfile: _editProfile,
              themeMode: _themeMode,
              onThemeModeChanged: _changeThemeMode,
              callbackLinkSettings: _callbackLinkSettings,
            ),
    );
  }
}

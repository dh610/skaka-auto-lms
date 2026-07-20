import 'package:flutter/material.dart';

import '../features/attendance/presentation/attendance_screen.dart';
import '../features/profile/data/profile_store.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/profile/presentation/profile_setup_screen.dart';
import '../features/schedule/application/schedule_controller.dart';
import '../features/schedule/application/notification_scheduler.dart';
import '../features/schedule/data/schedule_store.dart';
import '../features/schedule/data/local_notification_scheduler.dart';
import 'app_theme.dart';
import 'theme_mode_store.dart';

class SkalaAttendanceApp extends StatefulWidget {
  const SkalaAttendanceApp({super.key, this.notificationScheduler});

  final NotificationScheduler? notificationScheduler;

  @override
  State<SkalaAttendanceApp> createState() => _SkalaAttendanceAppState();
}

class _SkalaAttendanceAppState extends State<SkalaAttendanceApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _profileStore = ProfileStore();
  final _themeModeStore = ThemeModeStore();
  late final NotificationScheduler _notificationScheduler;
  late final ScheduleController _scheduleController;
  UserProfile? _profile;
  bool _loading = true;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _notificationScheduler =
        widget.notificationScheduler ?? LocalNotificationScheduler();
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
    await _notificationScheduler.initialize();
    await _scheduleController.load();
  }

  @override
  void dispose() {
    _scheduleController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await _profileStore.load();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  Future<void> _saveInitialProfile(UserProfile profile) async {
    await _profileStore.save(profile);
    if (mounted) setState(() => _profile = profile);
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
          : AttendanceScreen(
              profile: _profile!,
              scheduleController: _scheduleController,
              notificationScheduler: _notificationScheduler,
              onEditProfile: _editProfile,
              themeMode: _themeMode,
              onThemeModeChanged: _changeThemeMode,
            ),
    );
  }
}

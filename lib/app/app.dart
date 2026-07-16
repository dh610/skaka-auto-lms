import 'package:flutter/material.dart';

import '../features/attendance/presentation/attendance_screen.dart';
import '../features/profile/data/profile_store.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/profile/presentation/profile_setup_screen.dart';
import '../features/schedule/application/schedule_controller.dart';
import '../features/schedule/data/schedule_store.dart';

class SkalaAttendanceApp extends StatefulWidget {
  const SkalaAttendanceApp({super.key});

  @override
  State<SkalaAttendanceApp> createState() => _SkalaAttendanceAppState();
}

class _SkalaAttendanceAppState extends State<SkalaAttendanceApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _profileStore = ProfileStore();
  final _scheduleController = ScheduleController(ScheduleStore());
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _scheduleController.load();
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B35FF)),
        useMaterial3: true,
      ),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _profile == null
          ? ProfileSetupScreen(onInitialSave: _saveInitialProfile)
          : AttendanceScreen(
              profile: _profile!,
              scheduleController: _scheduleController,
              onEditProfile: _editProfile,
            ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../attendance/data/callback_link_settings.dart';
import '../../profile/domain/user_profile.dart';
import '../../schedule/application/notification_scheduler.dart';
import '../domain/app_version.dart';

enum SettingsPermissionStatus { loading, allowed, needed, unavailable }

enum SettingsVersionStatus { loading, available, unavailable }

class SettingsController extends ChangeNotifier {
  SettingsController({
    required UserProfile initialProfile,
    required ThemeMode initialThemeMode,
    required bool isAndroid,
    required NotificationPermissionSettings notificationSettings,
    required CallbackLinkSettings callbackLinkSettings,
    required AppVersionProvider appVersionProvider,
    required Future<UserProfile?> Function() editProfile,
    required Future<void> Function(ThemeMode) persistThemeMode,
  }) : _profile = initialProfile,
       _themeMode = initialThemeMode,
       _dependencies = (
         isAndroid: isAndroid,
         notificationSettings: notificationSettings,
         callbackLinkSettings: callbackLinkSettings,
         appVersionProvider: appVersionProvider,
         editProfile: editProfile,
         persistThemeMode: persistThemeMode,
       );

  final ({
    bool isAndroid,
    NotificationPermissionSettings notificationSettings,
    CallbackLinkSettings callbackLinkSettings,
    AppVersionProvider appVersionProvider,
    Future<UserProfile?> Function() editProfile,
    Future<void> Function(ThemeMode) persistThemeMode,
  })
  _dependencies;

  UserProfile _profile;
  ThemeMode _themeMode;
  SettingsPermissionStatus _notificationStatus =
      SettingsPermissionStatus.loading;
  SettingsPermissionStatus _exactAlarmStatus = SettingsPermissionStatus.loading;
  SettingsPermissionStatus _callbackLinkStatus =
      SettingsPermissionStatus.loading;
  SettingsVersionStatus _versionStatus = SettingsVersionStatus.loading;
  AppVersion? _appVersion;
  int _refreshGeneration = 0;
  bool _profileEditInProgress = false;
  Future<void> _themePersistenceTail = Future<void>.value();
  bool _disposed = false;

  UserProfile get profile => _profile;
  ThemeMode get themeMode => _themeMode;
  SettingsPermissionStatus get notificationStatus => _notificationStatus;
  SettingsPermissionStatus get exactAlarmStatus => _exactAlarmStatus;
  SettingsPermissionStatus get callbackLinkStatus => _callbackLinkStatus;
  SettingsVersionStatus get versionStatus => _versionStatus;
  AppVersion? get appVersion => _appVersion;
  bool get profileEditInProgress => _profileEditInProgress;

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    _notificationStatus = SettingsPermissionStatus.loading;
    if (_dependencies.isAndroid) {
      _exactAlarmStatus = SettingsPermissionStatus.loading;
      _callbackLinkStatus = SettingsPermissionStatus.loading;
    }
    _versionStatus = SettingsVersionStatus.loading;
    _appVersion = null;
    _notifyIfActive(generation);

    await Future.wait([
      _refreshNotificationPermissions(generation),
      if (_dependencies.isAndroid) _refreshCallbackLink(generation),
      _refreshVersion(generation),
    ]);
  }

  Future<void> _refreshNotificationPermissions(int generation) async {
    try {
      final status = await _dependencies.notificationSettings
          .getPermissionStatus();
      if (!_isActive(generation)) return;
      _notificationStatus = _permissionStatus(status.notificationsAllowed);
      if (_dependencies.isAndroid) {
        _exactAlarmStatus = _permissionStatus(status.exactAlarmsAllowed);
      }
    } catch (_) {
      if (!_isActive(generation)) return;
      _notificationStatus = SettingsPermissionStatus.unavailable;
      if (_dependencies.isAndroid) {
        _exactAlarmStatus = SettingsPermissionStatus.unavailable;
      }
    }
    _notifyIfActive(generation);
  }

  Future<void> _refreshCallbackLink(int generation) async {
    try {
      final enabled = await _dependencies.callbackLinkSettings.isEnabled();
      if (!_isActive(generation)) return;
      _callbackLinkStatus = _permissionStatus(enabled);
    } catch (_) {
      if (!_isActive(generation)) return;
      _callbackLinkStatus = SettingsPermissionStatus.unavailable;
    }
    _notifyIfActive(generation);
  }

  Future<void> _refreshVersion(int generation) async {
    try {
      final version = await _dependencies.appVersionProvider.getAppVersion();
      if (!_isActive(generation)) return;
      _appVersion = version;
      _versionStatus = SettingsVersionStatus.available;
    } catch (_) {
      if (!_isActive(generation)) return;
      _appVersion = null;
      _versionStatus = SettingsVersionStatus.unavailable;
    }
    _notifyIfActive(generation);
  }

  SettingsPermissionStatus _permissionStatus(bool? allowed) =>
      switch (allowed) {
        true => SettingsPermissionStatus.allowed,
        false => SettingsPermissionStatus.needed,
        null => SettingsPermissionStatus.unavailable,
      };

  Future<String?> openNotificationSettings() => _openSettings(
    _dependencies.notificationSettings.openNotificationSettings,
    '알림 설정 화면을 열지 못했습니다.',
  );

  Future<String?> openExactAlarmSettings() => _openSettings(
    _dependencies.notificationSettings.openExactAlarmSettings,
    '정확한 알람 설정 화면을 열지 못했습니다.',
  );

  Future<String?> openCallbackLinkSettings() => _openSettings(
    _dependencies.callbackLinkSettings.open,
    '앱 복귀 설정 화면을 열지 못했습니다.',
  );

  Future<String?> _openSettings(
    Future<void> Function() operation,
    String failureMessage,
  ) async {
    try {
      await operation();
      return null;
    } catch (_) {
      return failureMessage;
    }
  }

  Future<String?> editProfile() async {
    if (_disposed || _profileEditInProgress) return null;
    _profileEditInProgress = true;
    notifyListeners();
    try {
      final updated = await _dependencies.editProfile();
      if (updated != null && !_disposed) {
        _profile = updated;
      }
      return null;
    } catch (_) {
      return '사용자 정보를 변경하지 못했습니다.';
    } finally {
      if (!_disposed) {
        _profileEditInProgress = false;
        notifyListeners();
      }
    }
  }

  Future<String?> selectTheme(ThemeMode themeMode) async {
    if (_disposed || _themeMode == themeMode) return null;
    _themeMode = themeMode;
    notifyListeners();
    final persistence = _themePersistenceTail.then(
      (_) => _dependencies.persistThemeMode(themeMode),
    );
    _themePersistenceTail = persistence.then<void>((_) {}, onError: (_) {});
    try {
      await persistence;
      return null;
    } catch (_) {
      return '테마 설정을 저장하지 못했습니다.';
    }
  }

  bool _isActive(int generation) =>
      !_disposed && generation == _refreshGeneration;

  void _notifyIfActive(int generation) {
    if (_isActive(generation)) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshGeneration += 1;
    super.dispose();
  }
}

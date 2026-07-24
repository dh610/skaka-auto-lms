/// Immutable version metadata supplied by the installed application package.
class AppVersion {
  const AppVersion({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.version == version &&
      other.buildNumber == buildNumber;

  @override
  int get hashCode => Object.hash(version, buildNumber);
}

abstract interface class AppVersionProvider {
  Future<AppVersion> getAppVersion();
}

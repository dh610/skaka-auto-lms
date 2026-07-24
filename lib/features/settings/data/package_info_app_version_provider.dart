import 'package:package_info_plus/package_info_plus.dart';

import '../domain/app_version.dart';

/// Reads version metadata from the package installed on the device.
class PackageInfoAppVersionProvider implements AppVersionProvider {
  PackageInfoAppVersionProvider({
    Future<PackageInfo> Function()? loadPackageInfo,
  }) : _loadPackageInfo = loadPackageInfo ?? PackageInfo.fromPlatform;

  final Future<PackageInfo> Function() _loadPackageInfo;

  @override
  Future<AppVersion> getAppVersion() async {
    final packageInfo = await _loadPackageInfo();
    return AppVersion(
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
    );
  }
}

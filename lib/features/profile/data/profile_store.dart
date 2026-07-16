import 'package:shared_preferences/shared_preferences.dart';

import '../domain/user_profile.dart';

class ProfileStore {
  static const _nameKey = 'profile.name';
  static const _regionKey = 'profile.region';
  static const _classNumberKey = 'profile.classNumber';

  Future<UserProfile?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final name = preferences.getString(_nameKey);
    final regionId = preferences.getString(_regionKey);
    final classNumber = preferences.getInt(_classNumberKey);
    if (name == null || regionId == null || classNumber == null) return null;
    try {
      final region = CampusRegion.fromId(regionId);
      if (!region.classNumbers.contains(classNumber)) return null;
      return UserProfile(name: name, region: region, classNumber: classNumber);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(UserProfile profile) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nameKey, profile.name);
    await preferences.setString(_regionKey, profile.region.id);
    await preferences.setInt(_classNumberKey, profile.classNumber);
  }
}

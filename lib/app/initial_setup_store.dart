import 'package:shared_preferences/shared_preferences.dart';

class InitialSetupStore {
  static const _completedKey = 'initialSetup.completed';

  Future<bool> isCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_completedKey) ?? false;
  }

  Future<void> markCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completedKey, true);
  }

  Future<void> markIncomplete() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completedKey, false);
  }
}

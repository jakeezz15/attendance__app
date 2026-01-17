import 'package:shared_preferences/shared_preferences.dart';

class AuthLocalService {
  static const _key = 'isAdminLoggedIn';

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  static Future<void> logout() => setLoggedIn(false);
}

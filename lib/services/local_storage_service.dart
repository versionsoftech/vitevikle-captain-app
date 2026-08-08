import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _tokenKey = 'user_token';
  static const String _mobileKey = 'user_mobile';
  static const String _isLoggedInKey = 'is_logged_in';
  static const String _onboardingCompletedKey = 'onboarding_completed';
  static const String _driverIdKey = 'driver_id';
  static const String _driverStatusKey = 'driver_status';
  static const String _driverIsVerifiedKey = 'driver_is_verified';

  const LocalStorageService();

  Future<void> saveLogin({
    required bool isLoggedIn,
    String? token,
    String? mobile,
    String? driverId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, isLoggedIn);
    if (token != null) {
      await prefs.setString(_tokenKey, token);
    }
    if (mobile != null) {
      await prefs.setString(_mobileKey, mobile);
    }
    if (driverId != null) {
      await prefs.setString(_driverIdKey, driverId);
    }
  }

  Future<void> saveDriverSessionFlags({
    bool? status,
    bool? isVerified,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (status != null) {
      await prefs.setBool(_driverStatusKey, status);
    }
    if (isVerified != null) {
      await prefs.setBool(_driverIsVerifiedKey, isVerified);
    }
  }

  Future<bool> getLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getMobile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mobileKey);
  }

  Future<String?> getDriverId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_driverIdKey);
  }

  Future<bool> getDriverStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_driverStatusKey) ?? false;
  }

  Future<bool> getDriverIsVerified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_driverIsVerifiedKey) ?? false;
  }

  Future<void> clearLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_mobileKey);
    await prefs.remove(_driverIdKey);
    await prefs.remove(_driverStatusKey);
    await prefs.remove(_driverIsVerifiedKey);
    await prefs.setBool(_isLoggedInKey, false);
  }

  Future<bool> getOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompletedKey) ?? false;
  }

  Future<void> setOnboardingCompleted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, value);
  }
}

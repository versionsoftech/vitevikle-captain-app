import 'package:vite_captain/services/api_service.dart';

class AppConfig {
  static Map<String, dynamic> settings = <String, dynamic>{};

  static Future<void> loadAppSettings() async {
    try {
      final res = await const ApiService().getAppSettings();
      if (res['success'] == true && res['data'] is Map) {
        settings = Map<String, dynamic>.from(res['data'] as Map);
      }
    } catch (_) {}
  }

  static Map<String, dynamic> rideSettings() {
    final raw = settings['ride_settings'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static num numRideSetting(String key, num fallback) {
    final rs = rideSettings();
    final v = rs[key];
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? fallback;
  }

  static int intRideSetting(String key, int fallback) {
    final n = numRideSetting(key, fallback);
    return n.isFinite ? n.round() : fallback;
  }
}


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

  static Map<String, dynamic> locationSettings() {
    final raw = settings['location_settings'];
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

  static String _str(dynamic value) => (value ?? '').toString().trim();

  /// Admin Location Settings → Type of map.
  static String typeOfMap() {
    final loc = locationSettings();
    final raw = _str(
      loc['type_of_map'] ?? loc['typeOfMap'] ?? loc['map_type'] ?? loc['mapType'],
    );
    return raw.isEmpty ? 'Google Map' : raw;
  }

  static bool get useMapple {
    final value = typeOfMap().toLowerCase();
    return value.contains('mapple') || value.contains('mappls') || value.contains('mapmyindia');
  }

  static bool get useGoogleMap => !useMapple;

  static String googleMapApiKey() {
    final loc = locationSettings();
    final key = _str(
      loc['google_map_api_key'] ??
          loc['googleMapApiKey'] ??
          loc['google_maps_api_key'] ??
          loc['googleMapsApiKey'],
    );
    return key;
  }

  static String mappleMapSdkKey() {
    final loc = locationSettings();
    return _str(
      loc['mapple_map_sdk_key'] ??
          loc['mappls_map_sdk_key'] ??
          loc['mappleMapSdkKey'] ??
          loc['mapplsMapSdkKey'],
    );
  }

  static String mappleRestKey() {
    final loc = locationSettings();
    return _str(
      loc['mapple_rest_key'] ??
          loc['mappls_rest_key'] ??
          loc['mappleRestKey'] ??
          loc['mapplsRestKey'],
    );
  }
}

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';

class ServiceZone {
  final String name;
  final List<List<double>> polygon;
  final List<String> serviceIds;

  const ServiceZone({
    required this.name,
    required this.polygon,
    this.serviceIds = const [],
  });
}

class ZoneService {
  ZoneService._();
  static final ZoneService instance = ZoneService._();

  List<ServiceZone>? _cache;
  DateTime? _loadedAt;
  String _appliedState = '';

  Future<List<ServiceZone>> zones({bool force = false}) async {
    final fresh = _cache != null &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 10);
    if (!force && fresh) return _cache!;

    final response = await DioClient.dio.get(
      '$baseUrl/v1/zones',
      options: Options(validateStatus: (_) => true),
    );
    final decoded = response.data;
    final rows = decoded is Map && decoded['data'] is List ? decoded['data'] as List : const [];
    final next = <ServiceZone>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final status = row['status'];
      final active = status == null || status == 1 || status == true || status == '1';
      if (!active) continue;
      final name = (row['name'] ?? row['zoneName'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      next.add(ServiceZone(
        name: name,
        polygon: _points(row['place_points'] ?? row['placePoints'] ?? row['locations']),
        serviceIds: _ids(row['service_ids'] ?? row['serviceIds']),
      ));
    }
    _cache = next;
    _loadedAt = DateTime.now();
    return next;
  }

  Future<String?> syncLocation(double lat, double lng) async {
    if (!lat.isFinite || !lng.isFinite) return null;
    final list = await zones();
    final match = zoneAt(lat, lng, list);
    if (match == null || match == _appliedState) return match;
    final token = (await const SessionService().getToken() ?? '').trim();
    if (token.isEmpty) return match;
    final res = await const ApiService().updateDriverProfile(
      token: token,
      state: match,
      country: 'India',
    );
    if (res['success'] == true) {
      _appliedState = match;
    }
    return match;
  }

  Future<List<String>> serviceIdsFor(String name) async {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return const [];
    final list = await zones();
    for (final zone in list) {
      if (zone.name.trim().toLowerCase() == wanted) return zone.serviceIds;
    }
    return const [];
  }

  String? zoneAt(double lat, double lng, List<ServiceZone> list) {
    for (final zone in list) {
      if (zone.polygon.length >= 3 && _inside(lat, lng, zone.polygon)) {
        return zone.name;
      }
    }
    return null;
  }

  List<List<double>> _points(dynamic raw) {
    var value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }
    if (value is Map && value['coordinates'] is List) value = value['coordinates'];
    if (value is! List) return const [];
    final points = <List<double>>[];
    for (final item in value) {
      double? lat;
      double? lng;
      if (item is List && item.length >= 2) {
        final a = double.tryParse('${item[0]}');
        final b = double.tryParse('${item[1]}');
        if (a == null || b == null) continue;
        if (a.abs() <= 90 && b.abs() > 90) {
          lat = a;
          lng = b;
        } else {
          lat = b;
          lng = a;
        }
      } else if (item is Map) {
        lat = double.tryParse('${item['lat'] ?? item['latitude'] ?? ''}');
        lng = double.tryParse('${item['lng'] ?? item['longitude'] ?? item['long'] ?? ''}');
      }
      if (lat == null || lng == null) continue;
      points.add([lat, lng]);
    }
    return points;
  }

  List<String> _ids(dynamic raw) {
    var value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }
    if (value is! List) return const [];
    return value
        .map((item) {
          if (item is Map) return '${item['_id'] ?? item['id'] ?? ''}'.trim();
          return '$item'.trim();
        })
        .where((id) => id.isNotEmpty)
        .toList();
  }

  bool _inside(double lat, double lng, List<List<double>> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final latI = polygon[i][0];
      final lngI = polygon[i][1];
      final latJ = polygon[j][0];
      final lngJ = polygon[j][1];
      final crosses = (latI > lat) != (latJ > lat);
      final denom = (latJ - latI) == 0 ? 0.0000001 : (latJ - latI);
      if (crosses && lng < (lngJ - lngI) * (lat - latI) / denom + lngI) {
        inside = !inside;
      }
    }
    return inside;
  }
}

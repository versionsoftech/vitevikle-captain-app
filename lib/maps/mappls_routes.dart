import 'package:dio/dio.dart';
import 'package:mappls_gl/mappls_gl.dart' as m;
import 'package:vite_captain/services/app_config.dart';
import 'package:vite_captain/services/dio_client.dart';

import 'mappls_map.dart';

class MapplsRoute {
  const MapplsRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  String get distanceText {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    final km = distanceMeters / 1000;
    return '${km >= 100 ? km.round() : km.toStringAsFixed(1)} km';
  }

  String get durationText {
    final totalMinutes = (durationSeconds / 60).round();
    if (totalMinutes < 1) return '1 min';
    if (totalMinutes < 60) return '$totalMinutes ${totalMinutes == 1 ? 'min' : 'mins'}';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    final h = '$hours ${hours == 1 ? 'hour' : 'hours'}';
    return minutes == 0 ? h : '$h $minutes ${minutes == 1 ? 'min' : 'mins'}';
  }
}

final Map<String, MapplsRoute> _routeCache = <String, MapplsRoute>{};

String _key(LatLng a, LatLng b) =>
    '${a.latitude.toStringAsFixed(5)},${a.longitude.toStringAsFixed(5)}|'
    '${b.latitude.toStringAsFixed(5)},${b.longitude.toStringAsFixed(5)}';

/// Driving route using the admin map provider (Google or Mapple).
Future<MapplsRoute?> fetchMapplsRoute(LatLng origin, LatLng destination) async {
  final cacheKey = '${AppConfig.useGoogleMap ? 'g' : 'm'}|${_key(origin, destination)}';
  final cached = _routeCache[cacheKey];
  if (cached != null) return cached;

  final route = AppConfig.useGoogleMap
      ? await _fetchGoogleRoute(origin, destination)
      : await _fetchMappleRoute(origin, destination);

  if (route == null) return null;
  if (_routeCache.length > 40) _routeCache.remove(_routeCache.keys.first);
  _routeCache[cacheKey] = route;
  return route;
}

Future<MapplsRoute?> _fetchMappleRoute(LatLng origin, LatLng destination) async {
  final response = await m.MapplsDirection(
    origin: origin,
    destination: destination,
    geometries: m.DirectionCriteria.GEOMETRY_POLYLINE6,
    overview: m.DirectionCriteria.OVERVIEW_FULL,
  ).callDirection();

  final routes = response?.routes ?? const <m.DirectionsRoute>[];
  if (routes.isEmpty) return null;
  final first = routes.first;
  final geometry = first.geometry ?? '';
  final points = geometry.isEmpty ? <LatLng>[origin, destination] : decodePolyline(geometry, precision: 6);

  return MapplsRoute(
    points: points.length >= 2 ? points : <LatLng>[origin, destination],
    distanceMeters: first.distance ?? 0,
    durationSeconds: first.duration ?? 0,
  );
}

Future<MapplsRoute?> _fetchGoogleRoute(LatLng origin, LatLng destination) async {
  final apiKey = AppConfig.googleMapApiKey();
  if (apiKey.isEmpty) return null;

  final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', <String, String>{
    'origin': '${origin.latitude},${origin.longitude}',
    'destination': '${destination.latitude},${destination.longitude}',
    'mode': 'driving',
    'key': apiKey,
  });

  try {
    final response = await DioClient.dio.get(
      uri.toString(),
      options: Options(validateStatus: (_) => true),
    );
    if ((response.statusCode ?? 0) != 200) return null;
    final data = response.data;
    if (data is! Map) return null;
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) return null;
    final route0 = routes.first;
    if (route0 is! Map) return null;
    final overview = route0['overview_polyline'];
    final encoded = overview is Map ? (overview['points'] ?? '').toString() : '';
    final points = encoded.isEmpty ? <LatLng>[origin, destination] : decodePolyline(encoded, precision: 5);
    final legs = route0['legs'];
    double distance = 0;
    double duration = 0;
    if (legs is List && legs.isNotEmpty && legs.first is Map) {
      final leg = legs.first as Map;
      final dist = leg['distance'];
      final dur = leg['duration'];
      if (dist is Map) distance = (dist['value'] as num?)?.toDouble() ?? 0;
      if (dur is Map) duration = (dur['value'] as num?)?.toDouble() ?? 0;
    }
    return MapplsRoute(
      points: points.length >= 2 ? points : <LatLng>[origin, destination],
      distanceMeters: distance,
      durationSeconds: duration,
    );
  } catch (_) {
    return null;
  }
}

List<LatLng> decodePolyline(String encoded, {int precision = 6}) {
  final factor = precision == 6 ? 1e6 : 1e5;
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  int next() {
    var result = 0;
    var shift = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    lat += next();
    if (index >= encoded.length) break;
    lng += next();
    points.add(LatLng(lat / factor, lng / factor));
  }
  return points;
}

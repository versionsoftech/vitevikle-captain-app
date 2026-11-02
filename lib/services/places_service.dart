import 'package:dio/dio.dart';
import 'package:mappls_gl/mappls_gl.dart' as m;
import 'package:vite_captain/services/app_config.dart';
import 'package:vite_captain/services/dio_client.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;
  final String primaryText;
  final String secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.primaryText,
    required this.secondaryText,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    final structured = (json['structured_formatting'] as Map<String, dynamic>?) ?? {};
    return PlaceSuggestion(
      placeId: json['place_id'] as String,
      description: json['description'] as String,
      primaryText: (structured['main_text'] ?? json['description'] ?? '').toString(),
      secondaryText: (structured['secondary_text'] ?? '').toString(),
    );
  }
}

class PlaceDetails {
  final double lat;
  final double lng;
  final String address;

  const PlaceDetails({
    required this.lat,
    required this.lng,
    required this.address,
  });
}

/// Place search for the active admin map provider (Google or Mapple).
class PlacesService {
  const PlacesService({this.apiKey});

  /// Optional override; when empty, uses admin Google Map API key.
  final String? apiKey;

  static final Map<String, List<PlaceSuggestion>> _autocompleteCache =
      <String, List<PlaceSuggestion>>{};
  static final Map<String, PlaceDetails> _detailsCache = <String, PlaceDetails>{};

  String get _googleKey {
    final override = (apiKey ?? '').trim();
    if (override.isNotEmpty) return override;
    return AppConfig.googleMapApiKey();
  }

  Future<Response<dynamic>> _safeGet(Uri uri) async {
    try {
      return await DioClient.dio.get(
        uri.toString(),
        options: Options(validateStatus: (_) => true),
      );
    } catch (_) {
      throw Exception('NETWORK_ERROR');
    }
  }

  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    String? sessionToken,
    String? language,
    String? components,
    double? locationLat,
    double? locationLng,
    int? radiusMeters,
  }) async {
    if (AppConfig.useGoogleMap) {
      return _googleAutocomplete(
        input,
        sessionToken: sessionToken,
        language: language,
        components: components,
        locationLat: locationLat,
        locationLng: locationLng,
        radiusMeters: radiusMeters,
      );
    }
    return _mappleAutocomplete(
      input,
      language: language,
      locationLat: locationLat,
      locationLng: locationLng,
    );
  }

  Future<List<PlaceSuggestion>> _mappleAutocomplete(
    String input, {
    String? language,
    double? locationLat,
    double? locationLng,
  }) async {
    final trimmed = input.trim();
    if (trimmed.length < 3) return [];

    final cacheKey = 'm:${trimmed.toLowerCase()}';
    final cached = _autocompleteCache[cacheKey];
    if (cached != null) return List<PlaceSuggestion>.from(cached);

    final m.AutoSuggestResponse? response;
    try {
      response = await m.MapplsAutoSuggest(
        query: trimmed,
        location: (locationLat != null && locationLng != null) ? m.LatLng(locationLat, locationLng) : null,
        responseLang: language,
      ).callAutoSuggest();
    } catch (_) {
      throw Exception('NETWORK_ERROR');
    }

    final suggestions = <PlaceSuggestion>[];
    for (final place in response?.suggestedLocations ?? const <m.ELocation>[]) {
      final name = (place.placeName ?? '').trim();
      final address = (place.placeAddress ?? '').trim();
      final id = (place.mapplsPin ?? '').trim().isNotEmpty ? place.mapplsPin!.trim() : '$name|$address';
      final description = [name, address].where((s) => s.isNotEmpty).join(', ');
      if (description.isEmpty) continue;
      final lat = place.latitude ?? place.entryLatitude;
      final lng = place.longitude ?? place.entryLongitude;
      if (lat != null && lng != null) {
        _detailsCache[id] = PlaceDetails(lat: lat, lng: lng, address: description);
      }
      suggestions.add(PlaceSuggestion(
        placeId: id,
        description: description,
        primaryText: name.isNotEmpty ? name : description,
        secondaryText: address,
      ));
    }

    if (_autocompleteCache.length > 40) {
      _autocompleteCache.remove(_autocompleteCache.keys.first);
    }
    _autocompleteCache[cacheKey] = suggestions;
    return List<PlaceSuggestion>.from(suggestions);
  }

  Future<List<PlaceSuggestion>> _googleAutocomplete(
    String input, {
    String? sessionToken,
    String? language,
    String? components,
    double? locationLat,
    double? locationLng,
    int? radiusMeters,
  }) async {
    final trimmed = input.trim();
    if (trimmed.length < 3) return [];
    final key = _googleKey;
    if (key.isEmpty) return [];

    final cacheKey = 'g:${trimmed.toLowerCase()}';
    final cached = _autocompleteCache[cacheKey];
    if (cached != null) return List<PlaceSuggestion>.from(cached);

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      <String, String>{
        'input': trimmed,
        'key': key,
        if (sessionToken != null) 'sessiontoken': sessionToken,
        if (language != null) 'language': language,
        if (components != null) 'components': components,
        if (locationLat != null && locationLng != null)
          'location': '${locationLat.toStringAsFixed(6)},${locationLng.toStringAsFixed(6)}',
        if (radiusMeters != null) 'radius': radiusMeters.toString(),
      },
    );

    final res = await _safeGet(uri);
    if ((res.statusCode ?? 0) != 200) throw Exception('NETWORK_ERROR');
    final data = res.data;
    if (data is! Map) throw Exception('NETWORK_ERROR');
    final predictions = data['predictions'];
    if (predictions is! List) return [];

    final suggestions = predictions
        .whereType<Map>()
        .map((item) => PlaceSuggestion.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);

    if (_autocompleteCache.length > 40) {
      _autocompleteCache.remove(_autocompleteCache.keys.first);
    }
    _autocompleteCache[cacheKey] = suggestions;
    return List<PlaceSuggestion>.from(suggestions);
  }

  Future<PlaceDetails> getPlaceDetails(
    String placeId, {
    String? sessionToken,
    String? language,
    String? description,
  }) async {
    if (AppConfig.useGoogleMap) {
      return _googlePlaceDetails(placeId, sessionToken: sessionToken, language: language);
    }
    return _mapplePlaceDetails(placeId, description: description);
  }

  Future<PlaceDetails> _mapplePlaceDetails(String placeId, {String? description}) async {
    final cached = _detailsCache[placeId];
    if (cached != null) return cached;

    try {
      if (!placeId.contains('|')) {
        final detail = await m.MapplsPlaceDetail(mapplsPin: placeId).callPlaceDetail();
        if (detail?.latitude != null && detail?.longitude != null) {
          final address = [detail!.placeName, detail.address]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(', ');
          return _detailsCache[placeId] = PlaceDetails(
            lat: detail.latitude!,
            lng: detail.longitude!,
            address: address.isNotEmpty ? address : (description ?? ''),
          );
        }
      }

      final query = (description ?? placeId.replaceAll('|', ', ')).trim();
      final geocode = await m.MapplsGeoCoding(address: query, itemCount: 1).callGeocoding();
      final hit = geocode?.results?.firstWhere(
        (r) => r.latitude != null && r.longitude != null,
        orElse: () => m.GeoCodeResult(),
      );
      if (hit?.latitude != null && hit?.longitude != null) {
        return _detailsCache[placeId] = PlaceDetails(
          lat: hit!.latitude!,
          lng: hit.longitude!,
          address: (hit.formattedAddress ?? query).trim(),
        );
      }
    } catch (_) {
      throw Exception('NETWORK_ERROR');
    }
    throw Exception('NETWORK_ERROR');
  }

  Future<PlaceDetails> _googlePlaceDetails(
    String placeId, {
    String? sessionToken,
    String? language,
  }) async {
    final cached = _detailsCache[placeId];
    if (cached != null) return cached;
    final key = _googleKey;
    if (key.isEmpty) throw Exception('NETWORK_ERROR');

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      <String, String>{
        'place_id': placeId,
        'fields': 'geometry,formatted_address,name',
        'key': key,
        if (sessionToken != null) 'sessiontoken': sessionToken,
        if (language != null) 'language': language,
      },
    );

    final res = await _safeGet(uri);
    if ((res.statusCode ?? 0) != 200) throw Exception('NETWORK_ERROR');
    final data = res.data;
    if (data is! Map) throw Exception('NETWORK_ERROR');
    final result = data['result'];
    if (result is! Map) throw Exception('NETWORK_ERROR');
    final geometry = result['geometry'];
    final location = geometry is Map ? geometry['location'] : null;
    if (location is! Map) throw Exception('NETWORK_ERROR');
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) throw Exception('NETWORK_ERROR');
    final address = (result['formatted_address'] ?? result['name'] ?? '').toString();
    return _detailsCache[placeId] = PlaceDetails(lat: lat, lng: lng, address: address);
  }
}

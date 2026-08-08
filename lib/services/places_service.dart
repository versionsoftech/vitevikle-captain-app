import 'dart:convert';

import 'package:dio/dio.dart';
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
    final structured =
        (json['structured_formatting'] as Map<String, dynamic>?) ?? {};
    return PlaceSuggestion(
      placeId: json['place_id'] as String,
      description: json['description'] as String,
      primaryText: (structured['main_text'] ?? json['description'] ?? '')
          .toString(),
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

class PlacesService {
  final String apiKey;

  const PlacesService({required this.apiKey});

  static final Map<String, List<PlaceSuggestion>> _autocompleteCache =
      <String, List<PlaceSuggestion>>{};

  Future<Response<dynamic>> _safeGet(Uri uri) async {
    try {
      return await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
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
    final trimmed = input.trim();
    if (trimmed.length < 3) return [];

    final cacheKey = trimmed.toLowerCase();
    final cached = _autocompleteCache[cacheKey];
    if (cached != null) return List<PlaceSuggestion>.from(cached);

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      <String, String>{
        'input': trimmed,
        'key': apiKey,
        if (sessionToken != null) 'sessiontoken': sessionToken,
        if (language != null) 'language': language,
        if (components != null) 'components': components,
        if (locationLat != null && locationLng != null)
          'location': '${locationLat.toStringAsFixed(6)},${locationLng.toStringAsFixed(6)}',
        if (radiusMeters != null) 'radius': radiusMeters.toString(),
      },
    );

    final res = await _safeGet(uri);
    final statusCode = res.statusCode ?? 0;
    if (statusCode != 200) {
      throw Exception('NETWORK_ERROR');
    }

    dynamic raw = res.data;
    if (raw is String) {
      raw = jsonDecode(raw);
    }
    final data = raw as Map<String, dynamic>;
    final status = data['status'] as String?;

    if (status != 'OK' && status != 'ZERO_RESULTS') {
      throw Exception('NETWORK_ERROR');
    }

    final preds = (data['predictions'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(PlaceSuggestion.fromJson)
        .toList(growable: false);

    if (_autocompleteCache.length > 40) {
      _autocompleteCache.remove(_autocompleteCache.keys.first);
    }
    _autocompleteCache[cacheKey] = preds;
    return List<PlaceSuggestion>.from(preds);
  }

  Future<PlaceDetails> getPlaceDetails(
    String placeId, {
    String? sessionToken,
    String? language,
  }) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      <String, String>{
        'place_id': placeId,
        'fields': 'geometry,formatted_address,name',
        'key': apiKey,
        if (sessionToken != null) 'sessiontoken': sessionToken,
        if (language != null) 'language': language,
      },
    );

    final res = await _safeGet(uri);
    final statusCode = res.statusCode ?? 0;
    if (statusCode != 200) {
      throw Exception('NETWORK_ERROR');
    }

    dynamic raw = res.data;
    if (raw is String) {
      raw = jsonDecode(raw);
    }
    final data = raw as Map<String, dynamic>;
    final status = data['status'] as String?;

    if (status != 'OK') {
      throw Exception('NETWORK_ERROR');
    }

    final result = data['result'] as Map<String, dynamic>;
    final geometry = result['geometry'] as Map<String, dynamic>;
    final location = geometry['location'] as Map<String, dynamic>;

    final address = (result['formatted_address'] as String?) ??
        (result['name'] as String?) ??
        '';

    return PlaceDetails(
      lat: (location['lat'] as num).toDouble(),
      lng: (location['lng'] as num).toDouble(),
      address: address,
    );
  }
}

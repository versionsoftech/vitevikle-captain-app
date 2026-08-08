import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';

class DistanceCalculateApi {
  const DistanceCalculateApi();

  Future<String?> calculateDistanceKm({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
  }) async {
    final uri = Uri.parse('$baseUrl/distance/calculate');

    try {
      final res = await DioClient.dio.post(
        uri.toString(),
        data: {
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'drop_lat': dropLat,
          'drop_lng': dropLng,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
      );

      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) return null;

      dynamic decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['success'] != true) return null;

      final value = decoded['distance_km'];
      if (value == null) return null;
      final str = value.toString().trim();
      return str.isEmpty ? null : str;
    } catch (_) {
      return null;
    }
  }
}


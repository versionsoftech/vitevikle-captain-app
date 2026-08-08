import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';

class FareCalculateResult {
  final double distance;
  final num baseFare;
  final double extraDistance;
  final num extraFare;
  final int totalFare;

  const FareCalculateResult({
    required this.distance,
    required this.baseFare,
    required this.extraDistance,
    required this.extraFare,
    required this.totalFare,
  });

  factory FareCalculateResult.fromJson(Map<String, dynamic> json) {
    final distance = (json['distance'] is num) ? (json['distance'] as num).toDouble() : 0.0;
    final extraDistance = (json['extra_distance'] is num) ? (json['extra_distance'] as num).toDouble() : 0.0;
    final baseFare = (json['base_fare'] is num) ? (json['base_fare'] as num) : num.tryParse((json['base_fare'] ?? '').toString()) ?? 0;
    final extraFare = (json['extra_fare'] is num) ? (json['extra_fare'] as num) : num.tryParse((json['extra_fare'] ?? '').toString()) ?? 0;
    final totalFare = (json['total_fare'] is num) ? (json['total_fare'] as num).round() : int.tryParse((json['total_fare'] ?? '').toString()) ?? 0;

    return FareCalculateResult(
      distance: distance,
      baseFare: baseFare,
      extraDistance: extraDistance,
      extraFare: extraFare,
      totalFare: totalFare,
    );
  }
}

class FareCalculateApi {
  const FareCalculateApi();

  Future<FareCalculateResult?> calculateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    required String vehicleTypeId,
  }) async {
    final uri = Uri.parse('$baseUrl/fare/calculate');

    try {
      final res = await DioClient.dio.post(
        uri.toString(),
        data: {
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'drop_lat': dropLat,
          'drop_lng': dropLng,
          'vehicle_type_id': vehicleTypeId,
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

      return FareCalculateResult.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}


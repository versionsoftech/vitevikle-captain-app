import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';

class ServiceVehicleModel {
  final String id;
  final String name;
  final String description;
  final int? maxSeat;
  final String image;
  final dynamic pricing;

  const ServiceVehicleModel({
    required this.id,
    required this.name,
    required this.description,
    required this.maxSeat,
    required this.image,
    required this.pricing,
  });

  factory ServiceVehicleModel.fromJson(Map<String, dynamic> json) {
    return ServiceVehicleModel(
      id: (json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      maxSeat: json['max_seat'] is num
          ? (json['max_seat'] as num).toInt()
          : int.tryParse((json['max_seat'] ?? '').toString()),
      image: (json['image'] ?? '').toString(),
      pricing: json['pricing'],
    );
  }
}

class VehiclesByServiceApi {
  const VehiclesByServiceApi();

  Future<List<ServiceVehicleModel>> getVehiclesByService(String serviceCategoryId) async {
    final uri = Uri.parse('$baseUrl/vehicles/by-service/$serviceCategoryId');

    try {
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return <ServiceVehicleModel>[];
      }

      dynamic decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) return <ServiceVehicleModel>[];
      if (decoded['success'] != true) return <ServiceVehicleModel>[];

      final data = decoded['data'];
      if (data is! List) return <ServiceVehicleModel>[];

      return data
          .whereType<Map<String, dynamic>>()
          .map(ServiceVehicleModel.fromJson)
          .toList(growable: false);
    } catch (_) {
      return <ServiceVehicleModel>[];
    }
  }
}


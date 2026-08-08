import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';

class VehicleTypeModel {
  final String objectId;
  final int id;
  final String name;
  final String slug;
  final int? maxSeat;
  final String image;

  const VehicleTypeModel({
    required this.objectId,
    required this.id,
    required this.name,
    required this.slug,
    required this.maxSeat,
    required this.image,
  });

  factory VehicleTypeModel.fromJson(Map<String, dynamic> json) {
    final String objectId = (json['_id'] ?? json['objectId'] ?? '').toString().trim();
    final dynamic rawId = json['id'];
    final int parsedId = rawId is num
        ? rawId.toInt()
        : int.tryParse((rawId ?? '').toString()) ?? 0;

    final dynamic rawMaxSeat = json['max_seat'];
    final int? maxSeat = rawMaxSeat == null
        ? null
        : (rawMaxSeat is num
            ? rawMaxSeat.toInt()
            : int.tryParse(rawMaxSeat.toString()));

    return VehicleTypeModel(
      objectId: objectId,
      id: parsedId != 0
          ? parsedId
          : (((json['slug'] ?? json['name'] ?? '').toString().trim().isNotEmpty
                      ? (json['slug'] ?? json['name']).toString().trim()
                      : 'vehicle')
                  .hashCode &
              0x7fffffff),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      maxSeat: maxSeat,
      image: (json['image'] ?? json['icon'] ?? '').toString(),
    );
  }

  String get imageUrl {
    final raw = image.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    // baseUrl includes '/api' already; media lives on the same host
    final origin = Uri.parse(baseUrl).origin;
    if (raw.startsWith('/')) return '$origin$raw';
    return '$origin/$raw';
  }

  String get fallbackImageUrl {
    final raw = image.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final primaryOrigin = Uri.parse(baseUrl).origin;
    final fallbackOrigin = primaryOrigin.replaceFirst('://adm.', '://admin.');
    if (raw.startsWith('/')) return '$fallbackOrigin$raw';
    return '$fallbackOrigin/$raw';
  }
}

class VehicleTypeDetailsModel {
  final String objectId;
  final String name;
  final String slug;
  final String description;
  final int? maxSeat;
  final String image;

  const VehicleTypeDetailsModel({
    required this.objectId,
    required this.name,
    required this.slug,
    required this.description,
    required this.maxSeat,
    required this.image,
  });

  factory VehicleTypeDetailsModel.fromJson(Map<String, dynamic> json) {
    final dynamic rawMaxSeat = json['max_seat'];
    final int? maxSeat = rawMaxSeat == null
        ? null
        : (rawMaxSeat is num
            ? rawMaxSeat.toInt()
            : int.tryParse(rawMaxSeat.toString()));

    return VehicleTypeDetailsModel(
      objectId: (json['_id'] ?? '').toString().trim(),
      name: (json['name'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      maxSeat: maxSeat,
      image: (json['image'] ?? json['icon'] ?? '').toString(),
    );
  }

  String get imageUrl {
    final raw = image.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final origin = Uri.parse(baseUrl).origin;
    if (raw.startsWith('/')) return '$origin$raw';
    return '$origin/$raw';
  }

  String get fallbackImageUrl {
    final raw = image.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final primaryOrigin = Uri.parse(baseUrl).origin;
    final fallbackOrigin = primaryOrigin.replaceFirst('://adm.', '://admin.');
    if (raw.startsWith('/')) return '$fallbackOrigin$raw';
    return '$fallbackOrigin/$raw';
  }
}

class VehicleTypeApi {
  const VehicleTypeApi();

  Future<List<VehicleTypeModel>> getVehicleTypes() async {
    final uri = Uri.parse('$baseUrl/vehicle-types');

    try {
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return <VehicleTypeModel>[];
      }

      dynamic decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) return <VehicleTypeModel>[];
      if (decoded['success'] != true) return <VehicleTypeModel>[];

      final data = decoded['data'];
      if (data is! List) return <VehicleTypeModel>[];

      return data
          .whereType<Map<String, dynamic>>()
          .map(VehicleTypeModel.fromJson)
          .toList(growable: false);
    } catch (_) {
      return <VehicleTypeModel>[];
    }
  }

  Future<VehicleTypeDetailsModel?> getVehicleTypeById({required String vehicleTypeId}) async {
    final id = vehicleTypeId.trim();
    if (id.isEmpty) return null;

    final uri = Uri.parse('$baseUrl/vehicle-types/$id');
    try {
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) return null;

      dynamic decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['success'] != true) return null;

      final data = decoded['data'];
      if (data is! Map) return null;
      return VehicleTypeDetailsModel.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }
}


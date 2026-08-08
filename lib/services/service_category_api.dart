import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';

class ServiceCategory {
  final String id;
  final String service;
  final String name;
  final String image;
  final String category;
  final String slug;

  const ServiceCategory({
    required this.id,
    required this.service,
    required this.name,
    required this.image,
    required this.category,
    required this.slug,
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      id: (json['_id'] ?? '').toString(),
      service: (json['service'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
    );
  }
}

class ServiceCategoryApi {
  const ServiceCategoryApi();

  Future<List<ServiceCategory>> fetchServiceCategories() async {
    final uri = Uri.parse('$baseUrl/service-categories');

    try {
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return <ServiceCategory>[];
      }

      dynamic decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! List) return <ServiceCategory>[];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ServiceCategory.fromJson)
          .toList(growable: false);
    } catch (_) {
      return <ServiceCategory>[];
    }
  }
}


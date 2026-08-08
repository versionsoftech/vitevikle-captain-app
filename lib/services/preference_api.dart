import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';

class PreferenceModel {
  final int id;
  final String name;
  final String icon;

  const PreferenceModel({
    required this.id,
    required this.name,
    required this.icon,
  });

  factory PreferenceModel.fromJson(Map<String, dynamic> json) {
    final dynamic rawId = json['id'];
    final int id = rawId is num
        ? rawId.toInt()
        : int.tryParse((rawId ?? '').toString()) ?? 0;

    return PreferenceModel(
      id: id,
      name: (json['name'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
    );
  }

  String get iconUrl {
    final raw = icon.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    // baseUrl includes '/api' already; media lives on the same host
    final origin = Uri.parse(baseUrl).origin;
    if (raw.startsWith('/')) return '$origin$raw';
    return '$origin/$raw';
  }
}

class PreferenceApi {
  const PreferenceApi();

  Future<List<PreferenceModel>> getPreferences() async {
    final uri = Uri.parse('$baseUrl/preferences');

    try {
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return <PreferenceModel>[];
      }

      dynamic decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) return <PreferenceModel>[];
      if (decoded['success'] != true) return <PreferenceModel>[];

      final data = decoded['data'];
      if (data is! List) return <PreferenceModel>[];

      return data
          .whereType<Map<String, dynamic>>()
          .map(PreferenceModel.fromJson)
          .where((p) => p.id != 0)
          .toList(growable: false);
    } catch (_) {
      return <PreferenceModel>[];
    }
  }
}


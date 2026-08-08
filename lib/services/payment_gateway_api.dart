import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';

class PaymentGatewayModel {
  final String name;
  final String serial;
  final String icon;

  const PaymentGatewayModel({
    required this.name,
    required this.serial,
    required this.icon,
  });

  factory PaymentGatewayModel.fromJson(Map<String, dynamic> json) {
    return PaymentGatewayModel(
      name: (json['name'] ?? '').toString(),
      serial: (json['serial'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
    );
  }

  String get iconUrl {
    final raw = icon.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final origin = Uri.parse(baseUrl).origin;
    if (raw.startsWith('/')) return '$origin$raw';
    return '$origin/$raw';
  }
}

class PaymentGatewayApi {
  const PaymentGatewayApi();

  Future<List<PaymentGatewayModel>> getPaymentGateways() async {
    final uri = Uri.parse('$baseUrl/payment-gateways');

    try {
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return <PaymentGatewayModel>[];
      }

      dynamic decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) return <PaymentGatewayModel>[];
      if (decoded['success'] != true) return <PaymentGatewayModel>[];

      final data = decoded['data'];
      if (data is! List) return <PaymentGatewayModel>[];

      return data
          .whereType<Map<String, dynamic>>()
          .map(PaymentGatewayModel.fromJson)
          .where((g) => g.serial.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return <PaymentGatewayModel>[];
    }
  }
}


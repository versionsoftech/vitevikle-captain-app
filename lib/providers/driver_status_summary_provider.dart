import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:dio/dio.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';

enum VerificationStatus {
  approved,
  pending,
  rejected,
}

VerificationStatus verificationStatusFromString(String value) {
  final v = value.trim().toLowerCase();
  if (v == 'approved') return VerificationStatus.approved;
  if (v == 'rejected') return VerificationStatus.rejected;
  return VerificationStatus.pending;
}

class DriverStatusSummary {
  const DriverStatusSummary({
    required this.documentStatus,
    required this.vehicleStatus,
    required this.bankStatus,
    required this.isAllApproved,
  });

  final VerificationStatus documentStatus;
  final VerificationStatus vehicleStatus;
  final VerificationStatus bankStatus;
  final bool isAllApproved;

  factory DriverStatusSummary.pending() {
    return const DriverStatusSummary(
      documentStatus: VerificationStatus.pending,
      vehicleStatus: VerificationStatus.pending,
      bankStatus: VerificationStatus.pending,
      isAllApproved: false,
    );
  }

  static DriverStatusSummary fromJson(Map<String, dynamic> json) {
    return DriverStatusSummary(
      documentStatus: verificationStatusFromString((json['document_status'] ?? 'pending').toString()),
      vehicleStatus: verificationStatusFromString((json['vehicle_status'] ?? 'pending').toString()),
      bankStatus: verificationStatusFromString((json['bank_status'] ?? 'pending').toString()),
      isAllApproved: json['is_all_approved'] == true,
    );
  }
}

class DriverStatusSummaryProvider extends ChangeNotifier {
  DriverStatusSummaryProvider();

  bool _disposed = false;

  DriverStatusSummary _summary = DriverStatusSummary.pending();
  bool _loading = false;
  String? _error;
  DateTime? _lastUpdated;

  DriverStatusSummary get summary => _summary;
  bool get loading => _loading;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;

  void _safeNotify() {
    if (_disposed) return;
    if (!hasListeners) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> refresh({bool silent = false}) async {
    if (_loading) return;

    if (!silent) {
      _loading = true;
      _error = null;
      _safeNotify();
    }

    try {
      final token = (await const SessionService().getToken() ?? '').trim();
      if (token.isEmpty) {
        _summary = DriverStatusSummary.pending();
        _error = 'Unauthorized';
        _lastUpdated = DateTime.now();
        return;
      }

      final uri = Uri.parse('$baseUrl/driver/registration-status');
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer $token',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      dynamic decoded;
      try {
        decoded = res.data;
        if (decoded is String) decoded = jsonDecode(decoded);
      } catch (_) {
        decoded = null;
      }

      final statusCode = res.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        final msg = (decoded is Map<String, dynamic>)
            ? (decoded['message'] ?? 'Request failed').toString()
            : 'Request failed';
        _error = msg;
        return;
      }

      if (decoded is Map<String, dynamic> && decoded['success'] == true) {
        _summary = DriverStatusSummary.fromJson(decoded);
        _error = null;
        _lastUpdated = DateTime.now();
        return;
      }

      _error = 'Unexpected response';
    } finally {
      _loading = false;
      _safeNotify();
    }
  }
}


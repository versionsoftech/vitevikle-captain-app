import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';

const String baseUrl = "https://adm.vitevikle.com/api";

class ApiService {
  const ApiService();

  static final Map<String, Future<Map<String, dynamic>>> _completeParcelInFlight = <String, Future<Map<String, dynamic>>>{};

  bool _isTrue(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'success' || s == 'ok';
  }

  // ========= SOS MODULE =========
  Future<Map<String, dynamic>> triggerSOS({
    required String token,
    required String driverId,
    required Map<String, dynamic> payload,
  }) async {
    print('========== SOS REQUEST ==========');
    print('PAYLOAD: $payload');
    print('DRIVER ID: $driverId');
    print('ENDPOINT: $baseUrl/driver/sos/trigger');

    final uri = Uri.parse('$baseUrl/driver/sos/trigger');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/driver/sos/trigger');

    try {
      Response response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'driver_id': driverId,
          ...payload,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      print('========== SOS RESPONSE ==========');
      print('STATUS CODE: ${response.statusCode}');
      print('RESPONSE DATA: ${response.data}');

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        // Retry without /api if applicable
        if (!baseUrl.toLowerCase().contains('/api')) {
          response = await DioClient.dio.post(
            fallbackUri.toString(),
            data: {
              'driver_id': driverId,
              ...payload,
            },
            options: Options(
              validateStatus: (_) => true,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${token.trim()}',
                'Cache-Control': 'no-cache',
                'Pragma': 'no-cache',
              },
            ),
          );
          print('========== SOS FALLBACK RESPONSE ==========');
          print('FALLBACK STATUS CODE: ${response.statusCode}');
          print('FALLBACK RESPONSE DATA: ${response.data}');
          final decoded2 = _tryDecode(response.data);
          return _asMapResponse(decoded2, statusCode: response.statusCode ?? 0);
        }
      }
      return decodedMap;
    } catch (error) {
      print('========== SOS ERROR ==========');
      print('ERROR: $error');
      return {'success': false, 'message': 'Failed to trigger SOS'};
    }
  }

  Future<Map<String, dynamic>> trackSOS({
    required String alertId,
    required double lat,
    required double lng,
    double? speed,
    double? direction,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/sos/track');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/driver/sos/track');

    try {
      Response response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'alert_id': alertId,
          'lat': lat,
          'lng': lng,
          if (speed != null) 'speed': speed,
          if (direction != null) 'direction': direction,
        },
        options: Options(validateStatus: (_) => true),
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return _asMapResponse(_tryDecode(response.data), statusCode: statusCode);
      }
      // Retry without /api
      response = await DioClient.dio.post(
        fallbackUri.toString(),
        data: {
          'alert_id': alertId,
          'lat': lat,
          'lng': lng,
          if (speed != null) 'speed': speed,
          if (direction != null) 'direction': direction,
        },
        options: Options(validateStatus: (_) => true),
      );
      return _asMapResponse(_tryDecode(response.data), statusCode: response.statusCode ?? 0);
    } catch (_) {
      return {'success': false, 'message': 'Failed to update SOS location'};
    }
  }

  bool _isParcelAcceptSuccess(Map<String, dynamic> payload, int statusCode) {
    if (statusCode < 200 || statusCode >= 300) return false;
    if (_isTrue(payload['success']) || _isTrue(payload['status'])) return true;
    final data = payload['data'];
    if (data is Map) {
      final driverStatus = (data['driver_status'] ?? data['driverStatus'] ?? '').toString().trim().toLowerCase();
      if (driverStatus == 'accepted') return true;
    }
    final driverStatus = (payload['driver_status'] ?? payload['driverStatus'] ?? '').toString().trim().toLowerCase();
    if (driverStatus == 'accepted') return true;
    final message = (payload['message'] ?? '').toString().trim().toLowerCase();
    return message.contains('accepted') || message.contains('success');
  }

  Future<Map<String, dynamic>> getDriverPaymentStatus({
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/payment-status/$rideId');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/driver/payment-status/$rideId');

    try {
      print('PAYMENT STATUS API HIT');
    } catch (_) {}

    try {
      Response response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      int statusCode = response.statusCode ?? 0;
      dynamic decoded = _tryDecode(response.data);
      Map<String, dynamic> payload = _asMapResponse(decoded, statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot GET');
      if (shouldRetry && fallbackUri.toString() != uri.toString()) {
        response = await DioClient.dio.get(
          fallbackUri.toString(),
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );
        statusCode = response.statusCode ?? 0;
        decoded = _tryDecode(response.data);
        payload = _asMapResponse(decoded, statusCode: statusCode);
      }

      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      try {
        final status = (payload['payment_status'] ?? '').toString();
        print('PAYMENT STATUS RESPONSE => $status');
      } catch (_) {}

      return payload;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> walletReceivedRide({
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/ride/wallet-received');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/ride/wallet-received');

    try {
      final payloadBody = {
        'ride_id': rideId,
        'rideId': rideId,
        'booking_id': rideId,
        'bookingId': rideId,
      };

      Response response = await DioClient.dio.post(
        uri.toString(),
        data: payloadBody,
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      int statusCode = response.statusCode ?? 0;
      dynamic decoded = _tryDecode(response.data);
      Map<String, dynamic> payload = _asMapResponse(decoded, statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot POST');
      if (shouldRetry && fallbackUri.toString() != uri.toString()) {
        response = await DioClient.dio.post(
          fallbackUri.toString(),
          data: payloadBody,
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );
        statusCode = response.statusCode ?? 0;
        decoded = _tryDecode(response.data);
        payload = _asMapResponse(decoded, statusCode: statusCode);
      }

      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Payment confirmation failed').toString(),
          'raw': payload,
        };
      }

      return payload;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> checkPaymentStatus({
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/checkPaymentStatus/$rideId');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/driver/checkPaymentStatus/$rideId');

    try {
      print('PAYMENT STATUS API CALLED: rideId=$rideId url=$uri');
    } catch (_) {}

    try {
      Response response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      int statusCode = response.statusCode ?? 0;
      dynamic decoded = _tryDecode(response.data);
      Map<String, dynamic> payload = _asMapResponse(decoded, statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot GET');
      if (shouldRetry && fallbackUri.toString() != uri.toString()) {
        response = await DioClient.dio.get(
          fallbackUri.toString(),
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );
        statusCode = response.statusCode ?? 0;
        decoded = _tryDecode(response.data);
        payload = _asMapResponse(decoded, statusCode: statusCode);
      }

      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      try {
        final status = (payload['payment_status'] ?? '').toString();
        print('PAYMENT STATUS RESPONSE => $status');
      } catch (_) {}

      return payload;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getAppSettings() async {
    final uri = Uri.parse('$baseUrl/app-settings');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getCancellationReasons({
    required String type,
  }) async {
    final safeType = type.trim().toLowerCase();
    final uri = Uri.parse('$baseUrl/cancellation-reasons');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        queryParameters: {
          'type': safeType,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      final statusCode = response.statusCode ?? 0;
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Map<String, dynamic> _asMapResponse(dynamic decoded, {int statusCode = 0}) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    if (decoded is String) {
      final msg = decoded.trim();
      final lowered = msg.toLowerCase();
      final ok = (statusCode >= 200 && statusCode < 300) && (lowered == 'success' || lowered.contains('success'));
      return {
        'success': ok,
        'message': msg.isEmpty ? (ok ? 'Success' : 'Request failed') : msg,
        'raw': decoded,
      };
    }

    return {
      'success': false,
      'message': 'Unexpected response format',
      'raw': decoded,
    };
  }

  dynamic _tryDecode(dynamic data) {
    try {
      if (data == null) return {};
      if (data is String) {
        return jsonDecode(data);
      }
      return data;
    } catch (e) {
      return data;
    }
  }

  Future<Map<String, dynamic>> getCompletedParcels({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/parcel/completed');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'data': const <dynamic>[],
          'raw': payload,
        };
      }

      final list = payload['data'] is List ? (payload['data'] as List) : const <dynamic>[];
      return {
        'success': true,
        'data': list,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
        'data': const <dynamic>[],
      };
    }
  }

  Future<Map<String, dynamic>> getCancelledParcels({
    required String token,
  }) async {
    final urls = <String>[
      '$baseUrl/driver/parcel/cancelled',
      '$baseUrl/driver/parcel/canceled',
    ];

    for (final u in urls) {
      try {
        final response = await DioClient.dio.get(
          u,
          options: Options(
            validateStatus: (_) => true,
            headers: {
              'Authorization': 'Bearer ${token.trim()}',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        final statusCode = response.statusCode ?? 0;
        final decoded = _tryDecode(response.data);
        final payload = _asMapResponse(decoded, statusCode: statusCode);

        if (statusCode < 200 || statusCode >= 300) {
          continue;
        }

        final list = payload['data'] is List ? (payload['data'] as List) : const <dynamic>[];
        return {
          'success': true,
          'data': list,
        };
      } catch (_) {
        continue;
      }
    }

    return {
      'success': false,
      'message': 'Something went wrong. Please try again.',
      'data': const <dynamic>[],
    };
  }

  Future<Map<String, dynamic>> completeParcelRide({
    required String token,
    required String parcelId,
  }) async {
    final key = parcelId.trim();
    if (key.isNotEmpty) {
      final existing = _completeParcelInFlight[key];
      if (existing != null) {
        return await existing;
      }
    }

    final Future<Map<String, dynamic>> task = () async {
      final uri = Uri.parse('$baseUrl/driver/parcel/complete');

      try {
        final response = await DioClient.dio.post(
          uri.toString(),
          data: {
            'parcel_id': parcelId,
            'parcelId': parcelId,
            'id': parcelId,
          },
          options: Options(
            validateStatus: (_) => true,
            headers: {
              'Authorization': 'Bearer ${token.trim()}',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        final statusCode = response.statusCode ?? 0;
        final decoded = _tryDecode(response.data);
        final payload = _asMapResponse(decoded, statusCode: statusCode);

        final ok = statusCode >= 200 && statusCode < 300 && (_isTrue(payload['success']) || _isTrue(payload['status']));
        if (!ok) {
          return {
            'success': false,
            'message': (payload['message'] ?? 'Failed to complete ride').toString(),
            'raw': payload,
          };
        }

        return {
          'success': true,
          'data': payload['data'],
          'raw': payload,
        };
      } catch (_) {
        return {
          'success': false,
          'message': 'Something went wrong. Please try again.',
        };
      } finally {
        if (key.isNotEmpty) {
          _completeParcelInFlight.remove(key);
        }
      }
    }();

    if (key.isNotEmpty) {
      _completeParcelInFlight[key] = task;
    }
    return await task;
  }

  Future<Map<String, dynamic>> markParcelPaymentPending({
    required String token,
    required String parcelId,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/parcel/mark-payment-pending');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'parcel_id': parcelId,
          'parcelId': parcelId,
          'id': parcelId,
          'payment_status': 'payment_pending',
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      final ok = statusCode >= 200 && statusCode < 300 && (_isTrue(payload['success']) || _isTrue(payload['status']));
      if (!ok) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Failed to update payment status').toString(),
          'raw': payload,
        };
      }

      return {
        'success': true,
        'data': payload['data'],
        'raw': payload,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> getUpcomingParcels({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/parcel/upcoming');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'data': const <dynamic>[],
          'raw': payload,
        };
      }

      final list = payload['data'] is List ? (payload['data'] as List) : const <dynamic>[];
      return {
        'success': true,
        'data': list,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
        'data': const <dynamic>[],
      };
    }
  }

  Future<Map<String, dynamic>> verifyParcelPickupOtp({
    required String token,
    required String parcelId,
    required String otp,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/parcel/verify-pickup-otp');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'parcel_id': parcelId,
          'parcelId': parcelId,
          'otp': otp,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      final ok = statusCode >= 200 && statusCode < 300 && (payload['success'] == true || payload['status'] == true);
      if (!ok) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'OTP verification failed').toString(),
          'raw': payload,
        };
      }

      return {
        'success': true,
        'data': payload['data'],
        'raw': payload,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> getUserById({
    required String userId,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) {
      return {'success': false};
    }

    final uri = Uri.parse('$baseUrl/get-user-by-id/$id');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/get-user-by-id/$id');

    try {
      Response response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final dynamic decoded = response.data;
      final decodedMap = _tryDecodeMap(decoded);
      final statusCode = response.statusCode ?? 0;
      final payload = decodedMap ?? _asMapResponse(decoded, statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot GET') || message.contains('Cannot POST');
      if (shouldRetry && fallbackBase.isNotEmpty && fallbackBase != baseUrl) {
        response = await DioClient.dio.get(
          fallbackUri.toString(),
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        final dynamic decoded2 = response.data;
        final decodedMap2 = _tryDecodeMap(decoded2);
        final statusCode2 = response.statusCode ?? 0;
        final payload2 = decodedMap2 ?? _asMapResponse(decoded2, statusCode: statusCode2);
        return payload2;
      }

      return payload;
    } catch (_) {
      return {'success': false};
    }
  }

  Future<Map<String, dynamic>> getLiveParcelRequests({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/parcel/live-requests');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'data': const <dynamic>[],
          'raw': payload,
        };
      }

      final list = payload['data'] is List ? (payload['data'] as List) : const <dynamic>[];
      return {
        'success': true,
        'data': list,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
        'data': const <dynamic>[],
      };
    }
  }

  Future<Map<String, dynamic>> acceptParcelRequest({
    required String token,
    required String parcelId,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/parcel/accept');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'parcel_id': parcelId,
          'parcelId': parcelId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> rejectParcelRequest({
    required String token,
    required String parcelId,
    String? cancellationReasonId,
    String? reason,
    String? note,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/parcel/reject');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'parcel_id': parcelId,
          'parcelId': parcelId,
          if ((cancellationReasonId ?? '').trim().isNotEmpty) 'cancellation_reason_id': cancellationReasonId,
          if ((reason ?? '').trim().isNotEmpty) 'reason': reason,
          if ((note ?? '').trim().isNotEmpty) 'note': note,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }
      return payload;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> driverAcceptParcel({
    required String token,
    required String parcelId,
  }) async {
    final uri = Uri.parse('$baseUrl/parcel/driver/accept');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'parcel_id': parcelId,
          'parcelId': parcelId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> driverCancelParcel({
    required String token,
    required String parcelId,
    String? cancellationReasonId,
    String? reason,
    String? note,
  }) async {
    final uri = Uri.parse('$baseUrl/parcel/driver/cancel');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'parcel_id': parcelId,
          'parcelId': parcelId,
          if ((cancellationReasonId ?? '').trim().isNotEmpty) 'cancellation_reason_id': cancellationReasonId,
          if ((reason ?? '').trim().isNotEmpty) 'reason': reason,
          if ((note ?? '').trim().isNotEmpty) 'note': note,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getParcelStatus({
    required String parcelId,
  }) async {
    final uri = Uri.parse('$baseUrl/parcel/status/$parcelId');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getDriverWallet({
    required String driverId,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/wallet/$driverId');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/driver/wallet/$driverId');

    try {
      Response response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final dynamic decoded = response.data;
      final statusCode = response.statusCode ?? 0;
      final payload = _asMapResponse(_tryDecode(decoded), statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot GET');
      if (shouldRetry && fallbackUri.toString() != uri.toString()) {
        response = await DioClient.dio.get(
          fallbackUri.toString(),
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );
      }

      final statusCode2 = response.statusCode ?? 0;
      final payload2 = _asMapResponse(_tryDecode(response.data), statusCode: statusCode2);

      if (statusCode2 < 200 || statusCode2 >= 300) {
        return {
          'success': false,
          'message': (payload2['message'] ?? 'Request failed').toString(),
          'raw': payload2,
          'balance': 0.0,
          'transactions': const <dynamic>[],
        };
      }

      final balanceNum = payload2['balance'];
      final balance = balanceNum is num ? balanceNum.toDouble() : double.tryParse(balanceNum?.toString() ?? '') ?? 0.0;
      final tx = payload2['transactions'] is List ? (payload2['transactions'] as List) : const <dynamic>[];
      return {
        'success': true,
        'balance': balance,
        'transactions': tx,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
        'balance': 0.0,
        'transactions': const <dynamic>[],
      };
    }
  }

  Future<Map<String, dynamic>> updateDriverSettings({
    required String token,
    required bool rideEnabled,
    required bool intercityEnabled,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/update-settings');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'rideEnabled': rideEnabled,
          'intercityEnabled': intercityEnabled,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> updateEmergencyContact({
    required String token,
    required String name,
    required String phone,
    String? relationship,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/emergency-contact');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'name': name.trim(),
          'phone': phone.trim(),
          if (relationship != null) 'relationship': relationship.trim(),
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final payload = _asMapResponse(decoded, statusCode: statusCode);

      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return payload;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> receiveIntercityPayment({
    required String token,
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/intercity/driver-payment-received');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'ride_id': rideId,
          'rideId': rideId,
          'driver_id': (await SessionService().getDriverId())?.trim() ?? '',
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> confirmPayment({
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/cash-received');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/cash-received');

    try {
      final payloadBody = {
        'ride_id': rideId,
        'rideId': rideId,
      };

      Response response = await DioClient.dio.post(
        uri.toString(),
        data: payloadBody,
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final dynamic decoded = response.data;
      final statusCode = response.statusCode ?? 0;
      final payload = _asMapResponse(_tryDecode(decoded), statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot POST');
      if (shouldRetry && fallbackUri.toString() != uri.toString()) {
        response = await DioClient.dio.post(
          fallbackUri.toString(),
          data: payloadBody,
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );
      }

      final statusCode2 = response.statusCode ?? 0;
      final payload2 = _asMapResponse(_tryDecode(response.data), statusCode: statusCode2);
      if (statusCode2 < 200 || statusCode2 >= 300) {
        return {
          'success': false,
          'message': (payload2['message'] ?? 'Request failed').toString(),
          'raw': payload2,
        };
      }

      return payload2;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> verifyOtpAndStartRide({
    required String token,
    required String rideId,
    required String otp,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/intercity/verify-otp-start-ride');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'rideId': rideId,
          'request_id': rideId,
          'requestId': rideId,
          'otp': otp,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> updateDriverServices({
    required String token,
    required String type,
    required bool status,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/update-services');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'type': type.trim().toLowerCase(),
          'status': status,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> rejectIntercityRequest({
    required String token,
    required String requestId,
    String? cancellationReasonId,
    String? reason,
    String? note,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/reject-intercity');

    try {
      final String safeReasonId = (cancellationReasonId ?? '').trim();
      final String safeReason = (reason ?? '').trim();
      final String safeNote = (note ?? '').trim();

      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'request_id': requestId,
          if (safeReasonId.isNotEmpty) 'cancellation_reason_id': safeReasonId,
          if (safeReason.isNotEmpty) 'reason': safeReason,
          if (safeNote.isNotEmpty) 'note': safeNote,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> acceptIntercityRequest({
    required String token,
    required String requestId,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/accept-intercity');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'request_id': requestId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> sendIntercityBid({
    required String token,
    required String rideId,
    required double price,
    int? timeMinutes,
    String? vehicleType,
    String? vehicleColor,
    String? vehicleNumber,
    String? vehicleName,
    String? arrivalTime,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/intercity/send-bid');

    final payload = {
      'ride_id': rideId,
      'price': price,
      if (timeMinutes != null) 'time': timeMinutes,
      if (timeMinutes != null) 'time_minutes': timeMinutes,
      if (timeMinutes != null) 'arrival_time_minutes': timeMinutes,
      if (vehicleType != null && vehicleType.isNotEmpty) 'vehicle_type': vehicleType,
      if (vehicleColor != null && vehicleColor.isNotEmpty) 'vehicle_color': vehicleColor,
      if (vehicleNumber != null && vehicleNumber.isNotEmpty) 'vehicle_number': vehicleNumber,
      if (vehicleName != null && vehicleName.isNotEmpty) 'vehicle_name': vehicleName,
      if (arrivalTime != null && arrivalTime.isNotEmpty) 'arrival_time': arrivalTime,
    };

    print('===== INTERCITY BID PAYLOAD =====');
    print('vehicleType=$vehicleType');
    print('vehicleColor=$vehicleColor');
    print('vehicleNumber=$vehicleNumber');
    print('vehicleName=$vehicleName');
    print('arrivalTime=$arrivalTime');
    print('arrivalTimeMinutes=$timeMinutes');
    print('==============================');

    print('===== FINAL BID PAYLOAD =====');
    print('$payload');
    print('=============================');

    print('Contains vehicle_type: ${payload.containsKey('vehicle_type')}');
    print('Contains vehicle_color: ${payload.containsKey('vehicle_color')}');
    print('Contains vehicle_number: ${payload.containsKey('vehicle_number')}');
    print('Contains arrival_time: ${payload.containsKey('arrival_time')}');
    print('Contains arrival_time_minutes: ${payload.containsKey('arrival_time_minutes')}');
    print('Contains time_minutes: ${payload.containsKey('time_minutes')}');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: payload,
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      print('===== INTERCITY BID RESPONSE =====');
      print('STATUS: ${response.statusCode}');
      print('BODY: ${response.data}');
      print('================================');

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> completeIntercityRide({
    required String token,
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/intercity/complete');

    try {
      print('INTERCITY COMPLETE API CALL: ${uri.toString()}');
      print('INTERCITY COMPLETE DATA: rideId=$rideId');
      
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'request_id': rideId,
          'requestId': rideId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      print('INTERCITY COMPLETE STATUS CODE: $statusCode');
      print('INTERCITY COMPLETE RESPONSE: ${response.data}');
      
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);
      
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (e) {
      print('INTERCITY COMPLETE ERROR: $e');
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> confirmCashReceived({
    required String token,
    required String rideId,
    String rideType = 'normal',
  }) async {
    print('CONFIRM CASH RECEIVED API CALL');
    print('RIDE TYPE: $rideType');
    print('RIDE ID: $rideId');

    // Determine endpoint based on ride type
    String endpoint;
    Map<String, dynamic> payload;

    if (rideType == 'intercity') {
      endpoint = '$baseUrl/driver/intercity/confirm-cash-received';
      payload = {
        'request_id': rideId,
        'requestId': rideId,
      };
      print('API URL: $endpoint (INTERCITY)');
    } else {
      // Default to regular ride endpoint for normal and parcel rides
      endpoint = '$baseUrl/driver/cash-received';
      payload = {
        'ride_id': rideId,
        'rideId': rideId,
      };
      print('API URL: $endpoint (REGULAR)');
    }

    try {
      Response response = await DioClient.dio.post(
        endpoint,
        data: payload,
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      print('STATUS CODE: $statusCode');
      print('RESPONSE: ${response.data}');

      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);

      return decodedMap;
    } catch (e) {
      print('CONFIRM CASH RECEIVED ERROR: $e');
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getIntercityRequests({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/intercity-requests');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getMyWaitingIntercityRides({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/intercity/my-waiting');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getMyAcceptedIntercityRides({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/intercity/my-accepted');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      print('========== DRIVER APP RAW API RESPONSE ==========');
      print('STATUS: ${response.statusCode}');
      print('BODY: ${response.data}');
      print('=================================================');

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      print('========== DRIVER APP PARSED RIDE DATA ==========');
      print('SUCCESS: ${decoded['success']}');
      if (decoded['data'] is Map) {
        print('DATA KEYS: ${(decoded['data'] as Map).keys.toList()}');
      }
      print('====================================================');

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Map<String, dynamic>? _tryDecodeMap(dynamic data) {
    try {
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String) {
        final dynamic decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<Map<String, dynamic>> setRideEta({
    required String rideId,
    required int etaMinutes,
  }) async {
    final endpoints = <String>[
      '$baseUrl/ride/set-eta',
      '$baseUrl/ride/update-arrival-time',
    ];

    Object? lastError;
    for (final endpoint in endpoints) {
      try {
        final response = await DioClient.dio.post(
          endpoint,
          data: {
            'rideId': rideId,
            'etaMinutes': etaMinutes,
            'ride_id': rideId,
            'eta_minutes': etaMinutes,
            'started_at': DateTime.now().toUtc().toIso8601String(),
            'etaStartTime': DateTime.now().toUtc().toIso8601String(),
          },
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        final decoded = _tryDecode(response.data);
        final statusCode = response.statusCode ?? 0;
        final decodedMap = _asMapResponse(decoded, statusCode: statusCode);

        if (statusCode >= 200 && statusCode < 300 && decodedMap['success'] != false) {
          return {
            ...decodedMap,
            'success': true,
            'etaMinutes': etaMinutes,
          };
        }
        lastError = decodedMap['message'] ?? 'Request failed';
      } catch (e) {
        lastError = e;
      }
    }

    return {
      'success': false,
      'message': (lastError ?? 'Something went wrong. Please try again.').toString(),
    };
  }

  Future<Map<String, dynamic>> updatePaymentMethod({
    required String rideId,
    required String paymentMethod,
  }) async {
    final uri = Uri.parse('$baseUrl/update-payment-method');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'ride_id': rideId,
          'rideId': rideId,
          'payment_method': paymentMethod,
          'paymentMethod': paymentMethod,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);

      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> cashReceived({
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/cash-received');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/cash-received');

    print('RECEIVED BUTTON');
    print('RIDE ID: $rideId');
    print('URL: $uri');
    print('FALLBACK URL: $fallbackUri');
    print('METHOD: POST');

    try {
      final payloadBody = {
        'ride_id': rideId,
        'rideId': rideId,
        'booking_id': rideId,
        'bookingId': rideId,
        'status': 'confirmed',
      };

      print('BODY: $payloadBody');

      Response response = await DioClient.dio.post(
        uri.toString(),
        data: payloadBody,
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final dynamic decoded = response.data;
      final decodedMap = _tryDecodeMap(decoded);
      final statusCode = response.statusCode ?? 0;
      final payload = decodedMap ?? _asMapResponse(decoded, statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final hasApiBase = baseUrl.toLowerCase().contains('/api');
      final shouldRetry = !hasApiBase && (statusCode == 404 || message.contains('Cannot POST'));
      if (shouldRetry && fallbackBase.isNotEmpty && fallbackBase != baseUrl) {
        response = await DioClient.dio.post(
          fallbackUri.toString(),
          data: payloadBody,
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        final dynamic decoded2 = response.data;
        final decodedMap2 = _tryDecodeMap(decoded2);
        final statusCode2 = response.statusCode ?? 0;
        final payload2 = decodedMap2 ?? _asMapResponse(decoded2, statusCode: statusCode2);

        if (statusCode2 < 200 || statusCode2 >= 300) {
          return {
            'success': false,
            'message': (payload2['message'] ?? 'Request failed').toString(),
            'raw': payload2,
          };
        }

        return payload2;
      }

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> completePayment({
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/complete-payment');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/complete-payment');

    try {
      final payloadBody = {
        'ride_id': rideId,
        'rideId': rideId,
        'booking_id': rideId,
        'bookingId': rideId,
      };

      Response response = await DioClient.dio.post(
        uri.toString(),
        data: payloadBody,
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final dynamic decoded = response.data;
      final decodedMap = _tryDecodeMap(decoded);
      final statusCode = response.statusCode ?? 0;
      final payload = decodedMap ?? _asMapResponse(decoded, statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot POST');
      if (shouldRetry && fallbackBase.isNotEmpty && fallbackBase != baseUrl) {
        response = await DioClient.dio.post(
          fallbackUri.toString(),
          data: payloadBody,
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        final dynamic decoded2 = response.data;
        final decodedMap2 = _tryDecodeMap(decoded2);
        final statusCode2 = response.statusCode ?? 0;
        final payload2 = decodedMap2 ?? _asMapResponse(decoded2, statusCode: statusCode2);

        if (statusCode2 < 200 || statusCode2 >= 300) {
          return {
            'success': false,
            'message': (payload2['message'] ?? 'Request failed').toString(),
            'raw': payload2,
          };
        }

        return payload2;
      }

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> getDriverReviews({
    required String driverId,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/my-reviews/$driverId');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/driver/my-reviews/$driverId');
    final legacyUri = Uri.parse('$baseUrl/driver-reviews/$driverId');
    final legacyFallbackUri = Uri.parse('$fallbackBase/driver-reviews/$driverId');

    try {
      Response response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final dynamic decoded = response.data;
      final decodedMap = _tryDecodeMap(decoded);
      final statusCode = response.statusCode ?? 0;
      final payload = decodedMap ?? _asMapResponse(decoded, statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot GET');

      Map<String, dynamic> finalPayload = payload;
      int finalStatusCode = statusCode;

      if (shouldRetry && fallbackBase.isNotEmpty && fallbackBase != baseUrl) {
        response = await DioClient.dio.get(
          fallbackUri.toString(),
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        final dynamic decoded2 = response.data;
        final decodedMap2 = _tryDecodeMap(decoded2);
        final statusCode2 = response.statusCode ?? 0;
        final payload2 = decodedMap2 ?? _asMapResponse(decoded2, statusCode: statusCode2);

        finalPayload = payload2;
        finalStatusCode = statusCode2;
      }

      if (finalStatusCode < 200 || finalStatusCode >= 300) {
        // fallback to legacy endpoint used by older builds
        Response legacyRes = await DioClient.dio.get(
          legacyUri.toString(),
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        dynamic legacyDecoded = legacyRes.data;
        final legacyMap = _tryDecodeMap(legacyDecoded);
        final legacyStatus = legacyRes.statusCode ?? 0;
        final legacyPayload = legacyMap ?? _asMapResponse(legacyDecoded, statusCode: legacyStatus);

        final legacyMessage = (legacyPayload['message'] ?? '').toString();
        final legacyShouldRetry = legacyStatus == 404 || legacyMessage.contains('Cannot GET');
        if (legacyShouldRetry && fallbackBase.isNotEmpty && fallbackBase != baseUrl) {
          legacyRes = await DioClient.dio.get(
            legacyFallbackUri.toString(),
            options: Options(
              validateStatus: (_) => true,
              headers: const {
                'Cache-Control': 'no-cache',
                'Pragma': 'no-cache',
              },
            ),
          );
          legacyDecoded = legacyRes.data;
        }

        final legacyMap2 = _tryDecodeMap(legacyDecoded);
        final legacyStatus2 = legacyRes.statusCode ?? 0;
        final legacyPayload2 = legacyMap2 ?? _asMapResponse(legacyDecoded, statusCode: legacyStatus2);

        if (legacyStatus2 < 200 || legacyStatus2 >= 300) {
          return {
            'success': false,
            'message': (legacyPayload2['message'] ?? 'Request failed').toString(),
            'raw': legacyPayload2,
          };
        }

        return legacyPayload2;
      }

      // normalize /driver/my-reviews response to { success, data: [] } for UI
      if (finalPayload['success'] == true && finalPayload['reviews'] is List) {
        final list = List.from(finalPayload['reviews'] as List);
        final data = list.map((e) {
          final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
          final rider = m['rider_id'] is Map ? Map<String, dynamic>.from(m['rider_id'] as Map) : <String, dynamic>{};
          final riderName = (m['rider_name'] ?? rider['fullName'] ?? rider['name'] ?? 'User').toString();
          final riderImage = (m['rider_image'] ?? rider['user_image'] ?? rider['image'] ?? rider['avatar'] ?? '').toString();
          return {
            '_id': m['_id'],
            'user_name': riderName,
            'user_image': riderImage,
            'rating': m['rating'],
            'comment': m['message'],
            'tags': m['tags'] is List ? List.from(m['tags'] as List) : <dynamic>[],
            'created_at': m['created_at'] ?? m['createdAt'],
          };
        }).toList();

        return {
          'success': true,
          'data': data,
        };
      }

      return finalPayload;
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> submitDriverReview({
    required String rideId,
    int? rating,
    String? comment,
  }) async {
    final uri = Uri.parse('$baseUrl/submit-driver-review');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/submit-driver-review');

    try {
      final payloadBody = {
        'ride_id': rideId,
        'rideId': rideId,
        if (rating != null) 'rating': rating,
        if (comment != null) 'comment': comment,
        if (comment != null) 'review': comment,
      };

      Response response = await DioClient.dio.post(
        uri.toString(),
        data: payloadBody,
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final dynamic decoded = response.data;
      final decodedMap = _tryDecodeMap(decoded);
      final statusCode = response.statusCode ?? 0;
      final payload = decodedMap ?? _asMapResponse(decoded, statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot POST');
      if (shouldRetry && fallbackBase.isNotEmpty && fallbackBase != baseUrl) {
        response = await DioClient.dio.post(
          fallbackUri.toString(),
          data: payloadBody,
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        final dynamic decoded2 = response.data;
        final decodedMap2 = _tryDecodeMap(decoded2);
        final statusCode2 = response.statusCode ?? 0;
        final payload2 = decodedMap2 ?? _asMapResponse(decoded2, statusCode: statusCode2);

        if (statusCode2 < 200 || statusCode2 >= 300) {
          return {
            'success': false,
            'message': (payload2['message'] ?? 'Request failed').toString(),
            'raw': payload2,
          };
        }
        return payload2;
      }

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> submitReview({
    required String rideId,
    String? reviewerId,
    String? reviewFor,
    int? rating,
    List<String>? tags,
    String? comment,
    String? type,
  }) async {
    // Primary route (as per backend spec): POST /api/submit-review
    final uri = Uri.parse('$baseUrl/submit-review');
    // Legacy/non-api deployments might expose /submit-review at server root.
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/submit-review');

    try {
      final payloadBody = {
        'ride_id': rideId,
        'rideId': rideId,
        if ((reviewFor ?? '').trim().isNotEmpty) 'user_id': reviewFor!.trim(),
        if ((reviewFor ?? '').trim().isNotEmpty) 'userId': reviewFor!.trim(),
        if ((reviewerId ?? '').trim().isNotEmpty) 'driver_id': reviewerId!.trim(),
        if ((reviewerId ?? '').trim().isNotEmpty) 'driverId': reviewerId!.trim(),
        if (rating != null) 'rating': rating,
        if (comment != null) 'comment': comment,
        if (comment != null) 'review': comment,
        if (tags != null) 'tags': tags,
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
      };

      Response response = await DioClient.dio.post(
        uri.toString(),
        data: payloadBody,
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final dynamic decoded = response.data;
      final decodedMap = _tryDecodeMap(decoded);
      final statusCode = response.statusCode ?? 0;
      final payload = decodedMap ?? _asMapResponse(decoded, statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot POST');
      if (shouldRetry && fallbackBase.isNotEmpty && fallbackBase != baseUrl) {
        response = await DioClient.dio.post(
          fallbackUri.toString(),
          data: payloadBody,
          options: Options(
            validateStatus: (_) => true,
            headers: const {
              'Content-Type': 'application/json',
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          ),
        );

        final dynamic decoded2 = response.data;
        final decodedMap2 = _tryDecodeMap(decoded2);
        final statusCode2 = response.statusCode ?? 0;
        final payload2 = decodedMap2 ?? _asMapResponse(decoded2, statusCode: statusCode2);

        if (statusCode2 < 200 || statusCode2 >= 300) {
          return {
            'success': false,
            'message': (payload2['message'] ?? 'Request failed').toString(),
            'raw': payload2,
          };
        }

        return payload2;
      }

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> endRide({
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/end-ride');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'ride_id': rideId,
          'rideId': rideId,
          'booking_id': rideId,
          'bookingId': rideId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final dynamic decoded = response.data;
      final decodedMap = _tryDecodeMap(decoded);
      final statusCode = response.statusCode ?? 0;
      final payload = decodedMap ?? _asMapResponse(decoded, statusCode: statusCode);

      if (!_isParcelAcceptSuccess(payload, statusCode)) {
        return {
          'success': false,
          'message': (payload['message'] ?? 'Request failed').toString(),
          'raw': payload,
        };
      }

      return {
        ...payload,
        'success': true,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> sendArrivalRequest({
    required String rideRequestId,
    required String driverId,
  }) async {
    final uri = Uri.parse('$baseUrl/send-arrival-request');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'rideRequestId': rideRequestId,
          'rideId': rideRequestId,
          'booking_id': rideRequestId,
          'bookingId': rideRequestId,
          'driverId': driverId,
          'driver_id': driverId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getRideStatus({
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/ride-status/$rideId');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);

      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getRideDetails({
    required String rideId,
  }) async {
    final uri = Uri.parse('$baseUrl/ride-details/$rideId');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);

      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> completeRide({
    required String token,
    required String rideRequestId, 
    required String driverId,
    bool isIntercity = false,
  }) async {
    final endpoint = isIntercity ? '/driver/intercity/complete' : '/ride/complete';
    final uri = Uri.parse('$baseUrl$endpoint');

    try {
      print('COMPLETE RIDE API CALL: ${uri.toString()}');
      print('COMPLETE RIDE DATA: rideRequestId=$rideRequestId, driverId=$driverId');
      
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'rideRequestId': rideRequestId,
          'rideId': rideRequestId,
          'booking_id': rideRequestId,
          'bookingId': rideRequestId,
          'driverId': driverId,
          'driver_id': driverId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      print('COMPLETE RIDE STATUS CODE: $statusCode');
      print('COMPLETE RIDE RESPONSE: ${response.data}');
      
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (e) {
      print('COMPLETE RIDE ERROR: $e');
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> driverArrived({
    required String rideId,
    required String driverId,
  }) async {
    final uri = Uri.parse('$baseUrl/ride/driver/arrived');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'rideId': rideId,
          'booking_id': rideId,
          'bookingId': rideId,
          'driverId': driverId,
          'driver_id': driverId,
          'status': 'arrived',
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> verifyRideOtp({
    required String rideId,
    required String otp,
  }) async {
    final uri = Uri.parse('$baseUrl/ride/verify-otp');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'rideId': rideId,
          'booking_id': rideId,
          'bookingId': rideId,
          'otp': otp,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getRideRequests() async {
    final uri = Uri.parse('$baseUrl/driver/get-ride-requests');

    try {
      final token = (await SessionService().getToken() ?? '').trim();
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final decoded = _tryDecode(response.data);
      final decodedMap = _asMapResponse(decoded, statusCode: statusCode);
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      return decodedMap;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getPendingRideRequests({
    required String driverId,
  }) async {
    final uri = Uri.parse('$baseUrl/ride/get-pending-requests');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        queryParameters: {
          'driverId': driverId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getMyActiveRide({
    required String driverId,
  }) async {
    final uri = Uri.parse('$baseUrl/ride/get-my-active-ride');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        queryParameters: {
          'driverId': driverId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getDriverActiveRide({
    required String driverId,
  }) async {
    final uri = Uri.parse('$baseUrl/ride/get-driver-active-ride');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        queryParameters: {
          'driverId': driverId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> startRide({
    required String rideRequestId,
    required String driverId,
  }) async {
    final uri = Uri.parse('$baseUrl/ride/start');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'rideRequestId': rideRequestId,
          'rideId': rideRequestId,
          'booking_id': rideRequestId,
          'bookingId': rideRequestId,
          'driverId': driverId,
          'driver_id': driverId,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> cancelRide({
    required String rideRequestId,
    required String cancelledBy,
    String? cancellationReasonId,
    String? reason,
    String? note,
  }) async {
    final uri = Uri.parse('$baseUrl/ride/cancel');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'rideRequestId': rideRequestId,
          'cancelledBy': cancelledBy,
          if ((cancellationReasonId ?? '').trim().isNotEmpty) 'cancellation_reason_id': cancellationReasonId,
          'reason': (reason ?? '').trim(),
          'note': (note ?? '').trim(),
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> placeRideBid({
    required String rideRequestId,
    required String driverId,
    required int price,
    String? paymentMethod,
  }) async {
    final uri = Uri.parse('$baseUrl/ride/place-bid');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'rideRequestId': rideRequestId,
          'driverId': driverId,
          'price': price,
          'payment_method': paymentMethod,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      final decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> updateDriverStatus({
    required String token,
    required bool isOnline,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/update-status');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'status': isOnline ? 'online' : 'offline',
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token.trim()}',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
          },
        ),
      );

      dynamic decoded;
      decoded = _tryDecode(response.data);

      if (decoded is Map<String, dynamic>) {
        final statusCode = response.statusCode ?? 0;
        if (statusCode < 200 || statusCode >= 300) {
          return {
            'success': false,
            'message': (decoded['message'] ?? 'Request failed').toString(),
            'raw': decoded,
          };
        }
        return decoded;
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return {'success': true};
      }
      return {'success': false, 'message': 'Request failed'};
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> pingDriver({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/ping');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: const {
          'status': 'online',
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getDriverProfile({
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/profile');

    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> updateDriverProfile({
    required String token,
    String? fullName,
    String? email,
    String? dateOfBirth,
    String? gender,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/profile');

    try {
      final data = <String, dynamic>{
        if (fullName != null) 'fullName': fullName.trim(),
        if (email != null) 'email': email.trim(),
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.trim(),
        if (gender != null) 'gender': gender.trim(),
      };

      final response = await DioClient.dio.post(
        uri.toString(),
        data: data,
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${token.trim()}',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }

      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> updateDriverLocation({
    required String token,
    required double lat,
    required double lng,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/update-location');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'lat': lat,
          'lng': lng,
          'isOnline': true,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${token.trim()}',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
          },
        ),
      );

      dynamic decoded;
      decoded = _tryDecode(response.data);

      if (decoded is Map<String, dynamic>) {
        final statusCode = response.statusCode ?? 0;
        if (statusCode < 200 || statusCode >= 300) {
          return {
            'success': false,
            'message': (decoded['message'] ?? 'Request failed').toString(),
            'raw': decoded,
          };
        }
        return decoded;
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return {'success': true};
      }
      return {'success': false, 'message': 'Request failed'};
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> submitDriverDocument({
    required String driverId,
    required String documentId,
    String? documentNo,
    String? expiredAt,
    String? frontImagePath,
    String? backImagePath,
    String? selfieImagePath,
  }) async {
    final uri = Uri.parse('$baseUrl/driver-documents/submit');

    try {
      final data = <String, dynamic>{
        'driver_id': driverId,
        'document_id': documentId,
        if (documentNo != null && documentNo.trim().isNotEmpty)
          'document_no': documentNo.trim(),
        if (expiredAt != null && expiredAt.trim().isNotEmpty)
          'expired_at': expiredAt.trim(),
      };

      Future<void> addFile(String field, String? path) async {
        final p = (path ?? '').trim();
        if (p.isEmpty) return;
        final file = File(p);
        if (!file.existsSync()) return;
        data[field] = await MultipartFile.fromFile(p);
      }

      await addFile('front_image', frontImagePath);
      await addFile('back_image', backImagePath);
      await addFile('selfie_image', selfieImagePath);

      final response = await DioClient.dio.post(
        uri.toString(),
        data: FormData.fromMap(data),
        options: Options(
          validateStatus: (_) => true,
          contentType: Headers.multipartFormDataContentType,
        ),
      );

      dynamic decoded = _tryDecode(response.data);

      if (decoded is Map<String, dynamic>) {
        final statusCode = response.statusCode ?? 0;
        if (statusCode < 200 || statusCode >= 300) {
          return {
            'success': false,
            'message': (decoded['message'] ?? 'Upload failed').toString(),
            'raw': decoded,
          };
        }
        return decoded;
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return {
          'success': true,
          'message': 'Document submitted successfully',
          'raw': response.data,
        };
      }
      return {
        'success': false,
        'message': 'Upload failed',
        'raw': response.data,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> driverDocumentsStatusCheck(String driverId) async {
    final uri = Uri.parse('$baseUrl/driver-documents/status-check/$driverId');
    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );
      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }
      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getDriverDocumentsTableByDriver(String driverId) async {
    final uri = Uri.parse('$baseUrl/driver-documents/by-driver/$driverId');
    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }
      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> getDriverDocumentConfigs() async {
    final uri = Uri.parse('$baseUrl/documents?type=driver');
    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }
      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> driverLogin(String mobile) async {
    final uri = Uri.parse('$baseUrl/driver/login');
    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {'mobile': mobile},
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
      );

      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }
      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> driverRegister({
    required String fullName,
    required String mobile,
    required String email,
    required String service,
    required String serviceCategories,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/register');
    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'fullName': fullName,
          'mobile': mobile,
          'email': email,
          'service': service,
          'serviceCategories': serviceCategories,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
      );

      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }
      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> uploadDriverDocuments({
    required String driverId,
    required String license,
    required String rc,
    required String insurance,
    required String profilePhoto,
  }) async {
    final uri = Uri.parse('$baseUrl/driver/upload-documents');
    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'driverId': driverId,
          'license': license,
          'rc': rc,
          'insurance': insurance,
          'profilePhoto': profilePhoto,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
      );

      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }
      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> driverDocumentStatus(String driverId) async {
    final uri = Uri.parse('$baseUrl/driver/document-status/$driverId');
    try {
      final response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
        ),
      );
      dynamic decoded = _tryDecode(response.data);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'message': 'Unexpected response format'};
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decoded['message'] ?? 'Request failed').toString(),
          'raw': decoded,
        };
      }
      return decoded;
    } catch (_) {
      return {'success': false, 'message': 'Something went wrong. Please try again.'};
    }
  }

  Future<Map<String, dynamic>> checkUser(String mobile) async {
    Future<Map<String, dynamic>> callEndpoint(String path) async {
      final uri = Uri.parse('$baseUrl$path');
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'phone': mobile,
          'country_code': '91',
          'mobile': mobile,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
      );

      Map<String, dynamic>? decodedMap;
      try {
        final dynamic decoded = _tryDecode(response.data);
        if (decoded is Map<String, dynamic>) decodedMap = decoded;
      } catch (_) {}

      if (decodedMap == null) {
        return {
          'success': false,
          'message': 'Unexpected response format',
        };
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
        };
      }

      return decodedMap;
    }

    try {
      Map<String, dynamic> raw = await callEndpoint('/user/check');
      if (raw['success'] != false) {
        return _normalizeCheckUserResponse(raw);
      }

      raw = await callEndpoint('/user/check-user');
      return _normalizeCheckUserResponse(raw);
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> checkUserDetails(String mobile, {String? token}) async {
    final uri = Uri.parse('$baseUrl/user/check-user-details');

    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      final trimmedToken = token?.trim();
      if (trimmedToken != null && trimmedToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $trimmedToken';
      }

      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'phone': mobile,
          'country_code': '91',
          'mobile': mobile,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: headers,
        ),
      );

      Map<String, dynamic>? decodedMap;
      try {
        final dynamic decoded = _tryDecode(response.data);
        if (decoded is Map<String, dynamic>) decodedMap = decoded;
      } catch (_) {}

      if (decodedMap == null) {
        return {
          'success': false,
          'message': 'Unexpected response format',
        };
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Request failed').toString(),
          'raw': decodedMap,
        };
      }

      final bool exists = decodedMap['exists'] == true ||
          decodedMap['user_exists'] == true ||
          decodedMap['userExists'] == true;

      return {
        'success': decodedMap['success'] == true,
        'exists': exists,
        'token': decodedMap['token'] is String ? decodedMap['token'] : null,
        'user': decodedMap['user'],
        'raw': decodedMap,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Map<String, dynamic> _normalizeCheckUserResponse(Map<String, dynamic> raw) {
    final bool exists =
        raw['exists'] == true || raw['user_exists'] == true || raw['userExists'] == true;
    final token = raw['token'];
    return {
      'success': true,
      'exists': exists,
      'token': token is String ? token : null,
      'raw': raw,
    };
  }

  Future<Map<String, dynamic>> loginUser(String mobile, String password) async {
    final uri = Uri.parse('$baseUrl/user/login-password');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'phone': mobile,
          'password': password,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
      );

      Map<String, dynamic>? decodedMap;
      try {
        final dynamic decoded = _tryDecode(response.data);
        if (decoded is Map<String, dynamic>) {
          decodedMap = decoded;
        }
      } catch (_) {}

      if (decodedMap != null) {
        final statusCode = response.statusCode ?? 0;
        if (statusCode >= 200 && statusCode < 300) {
          return decodedMap;
        }

        return {
          'success': false,
          'message': (decodedMap['message'] ?? 'Login failed').toString(),
        };
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return {
          'success': false,
          'message': 'Unexpected response format',
        };
      }

      return {
        'success': false,
        'message': 'Login failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> registerUser({
    required String name,
    required String email,
    required String mobile,
    required String referenceCode,
  }) async {
    final uri = Uri.parse('$baseUrl/user/register');

    try {
      final response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'fullName': name,
          'name': name,
          'email': email,
          'mobile': mobile,
          'phone': mobile,
          'country_code': '91',
          'couponCode': referenceCode,
          'referral_code': referenceCode,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
          },
        ),
      );

      Map<String, dynamic>? decodedMap;
      try {
        final dynamic decoded = _tryDecode(response.data);
        if (decoded is Map<String, dynamic>) {
          decodedMap = decoded;
        }
      } catch (_) {}

      if (decodedMap != null) {
        final statusCode = response.statusCode ?? 0;
        if (statusCode >= 200 && statusCode < 300) {
          return decodedMap;
        }

        return {
          'success': false,
          'message':
              (decodedMap['message'] ?? 'Registration failed').toString(),
        };
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode >= 200 && statusCode < 300) {
        return {
          'success': false,
          'message': 'Unexpected response format',
        };
      }

      return {
        'success': false,
        'message': 'Registration failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> createDriverWithdrawRequest({
    required double amount,
  }) async {
    final token = (await const SessionService().getToken())?.trim() ?? '';
    final uri = Uri.parse('$baseUrl/driver/wallet/withdraw-request');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/driver/wallet/withdraw-request');

    try {
      Response response = await DioClient.dio.post(
        uri.toString(),
        data: {
          'amount': amount,
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final payload = _asMapResponse(_tryDecode(response.data), statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot POST');
      if (shouldRetry && fallbackUri.toString() != uri.toString()) {
        response = await DioClient.dio.post(
          fallbackUri.toString(),
          data: {
            'amount': amount,
          },
          options: Options(
            validateStatus: (_) => true,
            headers: {
              'Content-Type': 'application/json',
              if (token.isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
            },
          ),
        );
      }

      final statusCode2 = response.statusCode ?? 0;
      final payload2 = _asMapResponse(_tryDecode(response.data), statusCode: statusCode2);

      if (statusCode2 < 200 || statusCode2 >= 300) {
        return {
          'success': false,
          'message': (payload2['message'] ?? 'Request failed').toString(),
          'raw': payload2,
        };
      }

      return {
        'success': true,
        'message': (payload2['message'] ?? '').toString(),
        'data': payload2,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  Future<Map<String, dynamic>> getDriverWithdrawHistory() async {
    final token = (await const SessionService().getToken())?.trim() ?? '';
    final uri = Uri.parse('$baseUrl/driver/wallet/withdraw-history');
    final fallbackBase = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final fallbackUri = Uri.parse('$fallbackBase/driver/wallet/withdraw-history');

    try {
      Response response = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            if (token.isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
          },
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final payload = _asMapResponse(_tryDecode(response.data), statusCode: statusCode);

      final message = (payload['message'] ?? '').toString();
      final shouldRetry = statusCode == 404 || message.contains('Cannot GET');
      if (shouldRetry && fallbackUri.toString() != uri.toString()) {
        response = await DioClient.dio.get(
          fallbackUri.toString(),
          options: Options(
            validateStatus: (_) => true,
            headers: {
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
              if (token.isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
            },
          ),
        );
      }

      final statusCode2 = response.statusCode ?? 0;
      final payload2 = _asMapResponse(_tryDecode(response.data), statusCode: statusCode2);
      if (statusCode2 < 200 || statusCode2 >= 300) {
        return {
          'success': false,
          'message': (payload2['message'] ?? 'Request failed').toString(),
          'data': const <dynamic>[],
          'raw': payload2,
        };
      }

      final list = payload2['data'] is List ? (payload2['data'] as List) : const <dynamic>[];
      return {
        'success': true,
        'data': list,
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
        'data': const <dynamic>[],
      };
    }
  }
}



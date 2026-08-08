import 'package:flutter/foundation.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/local_storage_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/app_config.dart';

class DriverAuthProvider extends ChangeNotifier {
  bool _loading = false;
  String? _error;
  String? _status;
  String? _driverId;

  bool get loading => _loading;
  String? get error => _error;
  String? get status => _status;
  String? get driverId => _driverId;

  Future<Map<String, dynamic>> login(String mobile) async {
    _loading = true;
    _error = null;
    notifyListeners();

    final result = await const ApiService().driverLogin(mobile);

    if (result['success'] == true) {
      final token = result['token'];
      final driverId = result['driverId']?.toString();
      final status = result['status']?.toString();

      bool? statusBool;
      final dynamic rawStatus = result['status'];
      if (rawStatus is bool) {
        statusBool = rawStatus;
      } else if (status != null) {
        final s = status.trim().toUpperCase();
        if (s == 'APPROVED') {
          statusBool = true;
        } else if (s == 'SUSPENDED' || s == 'PENDING' || s == 'VERIFIED' || s == 'DOCUMENT_PENDING' || s == 'NEW_DRIVER') {
          statusBool = false;
        }
      }

      await const LocalStorageService().saveLogin(
        isLoggedIn: true,
        token: token is String && token.trim().isNotEmpty ? token.trim() : null,
        mobile: mobile,
        driverId: (driverId != null && driverId.trim().isNotEmpty) ? driverId.trim() : null,
      );

      await const LocalStorageService().saveDriverSessionFlags(
        status: statusBool,
        isVerified: true,
      );

      if (token is String && token.trim().isNotEmpty) {
        await const SessionService().saveLoginSession(token: token.trim(), mobile: mobile);
      }
      if (driverId != null && driverId.trim().isNotEmpty) {
        await const SessionService().saveDriverId(driverId.trim());
      }

      await AppConfig.loadAppSettings();

      _driverId = driverId;
      _status = status;
    } else {
      _error = (result['message'] ?? 'Something went wrong').toString();
    }

    _loading = false;
    notifyListeners();
    return result;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}


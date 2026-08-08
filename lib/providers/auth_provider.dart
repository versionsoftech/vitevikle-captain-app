import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/modules/documents/driver_documents_upload_screen.dart';
import 'package:vite_captain/modules/registration/driver_registration_screen.dart';
import 'package:vite_captain/modules/status/driver_suspended_screen.dart';
import 'package:vite_captain/modules/status/driver_under_review_screen.dart';
import 'package:vite_captain/providers/driver_auth_provider.dart';
import 'package:vite_captain/screens/auth/otp_verification_screen.dart';
import 'package:vite_captain/screens/map_screen.dart';
import 'package:vite_captain/screens/first_launch_flow_screen.dart';
import 'package:vite_captain/services/firebase_auth_service.dart';
import 'package:vite_captain/services/session_service.dart';

// FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
// This provider now uses CustomOtpService instead of Firebase Phone Authentication
// All Firebase OTP methods have been commented out but preserved for potential future use

class AuthProvider extends ChangeNotifier {
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  String? _error;

  bool get sendingOtp => _sendingOtp;
  bool get verifyingOtp => _verifyingOtp;
  String? get error => _error;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
  // Future<void> sendOtp({
  //   required BuildContext context,
  //   required String mobile,
  // }) async {
  //   final m = mobile.trim().replaceAll(RegExp(r'\D'), '');
  //   if (m.isEmpty || m.length < 10) {
  //     _error = 'Please enter valid mobile number';
  //     notifyListeners();
  //     return;
  //   }

  //   _sendingOtp = true;
  //   _error = null;
  //   notifyListeners();

  //   final phoneNumber = '+91$m';

  //   await FirebaseAuthService.instance.sendOtp(
  //     phoneNumber: phoneNumber,
  //     onCodeSent: (verificationId, resendToken) {
  //       _sendingOtp = false;
  //       notifyListeners();

  //       Navigator.push(
  //         context,
  //         MaterialPageRoute(
  //           builder: (context) => OtpVerificationScreen(
  //             mobile: m,
  //             verificationId: verificationId,
  //             resendToken: resendToken,
  //           ),
  //         ),
  //       );
  //     },
  //     onFailed: (message) {
  //       _sendingOtp = false;
  //       _error = message;
  //       notifyListeners();
  //     },
  //     onAutoVerified: (_) {
  //       _sendingOtp = false;
  //       notifyListeners();
  //     },
  //   );
  // }

  // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
  // This method is no longer used with custom OTP
  // Future<Map<String, dynamic>> verifyOtpAndLogin({
  //   required BuildContext context,
  //   required PhoneAuthCredential credential,
  //   required String mobile,
  // }) async {
  //   _verifyingOtp = true;
  //   _error = null;
  //   notifyListeners();

  //   try {
  //     await FirebaseAuthService.instance.signInWithCredential(credential);
  //   } on FirebaseAuthException catch (e) {
  //     _verifyingOtp = false;
  //     if (e.code == 'invalid-verification-code') {
  //       _error = 'OTP failed';
  //     } else if (e.code == 'session-expired') {
  //       _error = 'OTP expired. Please resend OTP.';
  //     } else if (e.code == 'network-request-failed') {
  //       _error = 'Network error';
  //     } else {
  //       _error = e.message ?? 'OTP verification failed';
  //     }
  //     notifyListeners();
  //     return {'success': false, 'message': _error};
  //   } catch (_) {
  //     _verifyingOtp = false;
  //     _error = 'OTP verification failed';
  //     notifyListeners();
  //     return {'success': false, 'message': _error};
  //   }

  //   final result = await context.read<DriverAuthProvider>().login(mobile);

  //   _verifyingOtp = false;
  //   if (result['success'] != true) {
  //     _error = (result['message'] ?? 'Something went wrong').toString();
  //   }
  //   notifyListeners();
  //   return result;
  // }

  Future<void> handleDriverStatusRouting({
    required BuildContext context,
    required String mobile,
    required Map<String, dynamic> result,
    bool replaceAll = true,
  }) async {
    final status = (result['status'] ?? '').toString();
    final driverId = result['driverId']?.toString();

    Future<void> go(Widget page) async {
      if (!context.mounted) return;
      if (replaceAll) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => page),
          (route) => false,
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => page),
        );
      }
    }

    if (status == 'NEW_DRIVER') {
      await go(DriverRegistrationScreen(mobile: mobile));
      return;
    }

    if (status == 'DOCUMENT_PENDING') {
      final storedId = await const SessionService().getDriverId();
      final idToUse = (driverId != null && driverId.isNotEmpty) ? driverId : (storedId ?? '');
      if (idToUse.trim().isEmpty) {
        _error = 'Driver id not found. Please try again.';
        notifyListeners();
        return;
      }
      await go(const FirstLaunchFlowScreen(next: MapScreen()));
      return;
    }

    if (status == 'SUSPENDED') {
      await go(const DriverSuspendedScreen());
      return;
    }

    if (status == 'APPROVED') {
      await go(const FirstLaunchFlowScreen(next: MapScreen()));
      return;
    }

    if (status == 'PENDING' || status == 'VERIFIED') {
      await go(const DriverUnderReviewScreen());
      return;
    }

    _error = 'Unknown status: $status';
    notifyListeners();
  }
}


import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

// FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
// This service is now using CustomOtpService instead of Firebase Phone Authentication
// All Firebase OTP methods have been commented out but preserved for potential future use

class FirebaseAuthService {
  FirebaseAuthService._();

  static final FirebaseAuthService instance = FirebaseAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  PhoneAuthCredential? _autoCredential;
  final StreamController<PhoneAuthCredential> _autoCredentialController =
      StreamController<PhoneAuthCredential>.broadcast();
  bool _autoNotified = false;

  Stream<PhoneAuthCredential> get autoCredentialStream =>
      _autoCredentialController.stream;

  PhoneAuthCredential? consumeAutoCredential() {
    final c = _autoCredential;
    _autoCredential = null;
    return c;
  }

  // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
  // Future<void> sendOtp({
  //   required String phoneNumber,
  //   required void Function(String verificationId, int? resendToken) onCodeSent,
  //   required void Function(String message) onFailed,
  //   required void Function(PhoneAuthCredential credential) onAutoVerified,
  //   void Function(String verificationId)? onTimeout,
  //   int? forceResendingToken,
  // }) async {
  //   // reset one-shot guard per verification flow
  //   _autoNotified = false;
  //   await _auth.verifyPhoneNumber(
  //     phoneNumber: phoneNumber,
  //     timeout: const Duration(seconds: 20),
  //     forceResendingToken: forceResendingToken,
  //     verificationCompleted: (credential) {
  //       if (_autoNotified) return;
  //       _autoNotified = true;
  //       _autoCredential = credential;
  //       _autoCredentialController.add(credential);
  //       onAutoVerified(credential);
  //     },
  //     verificationFailed: (e) {
  //       onFailed(e.message ?? 'Verification failed');
  //     },
  //     codeSent: (verificationId, resendToken) {
  //       onCodeSent(verificationId, resendToken);
  //     },
  //     codeAutoRetrievalTimeout: (verificationId) {
  //       if (onTimeout != null) {
  //         onTimeout(verificationId);
  //       }
  //     },
  //   );
  // }

  // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
  // Future<UserCredential> signInWithCredential(PhoneAuthCredential credential) {
  //   return _auth.signInWithCredential(credential);
  // }

  // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
  // PhoneAuthCredential credentialFromSms({
  //   required String verificationId,
  //   required String smsCode,
  // }) {
  //   return PhoneAuthProvider.credential(
  //     verificationId: verificationId,
  //     smsCode: smsCode,
  //   );
  // }

  void dispose() {
    _autoCredentialController.close();
  }
}

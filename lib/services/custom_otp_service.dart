import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';

class CustomOtpService {
  CustomOtpService._();
  
  static final CustomOtpService instance = CustomOtpService._();
  
  final Dio _dio = Dio();
  
  // Store OTP in memory for verification
  String? _currentOtp;
  String? _currentMobile;
  DateTime? _otpExpiryTime;
  
  // OTP expiry duration (5 minutes)
  static const Duration _otpExpiryDuration = Duration(minutes: 5);
  static const String _testMobile = '9876543210';
  static const String _testOtp = '123456';
  
  // API Configuration
  static const String _authKey = 'Nkb77uDh1aGJoElg2F9MFl9YL5e7qd-cO7VuGGCH2CI';
  static const String _apiUrl = 'https://apitxt.com/api/sendOTP';
  
  // App Signature Hash for SMS Retriever API
  // This hash MUST be included at the end of the SMS for auto-read to work
  // Generated from device: u0czD5XQ8R/
  static const String _appSignatureHash = 'u0czD5XQ8R/';
  
  /// Generate a random 6-digit OTP
  String _generateOtp() {
    final random = Random();
    final otp = random.nextInt(900000) + 100000; // 100000 to 999999
    return otp.toString();
  }
  
  /// Send OTP to the given mobile number
  Future<Map<String, dynamic>> sendOtp({
    required String mobile,
  }) async {
    try {
      print('[CUSTOM OTP] Sending OTP to mobile: $mobile');
      
      // Validate mobile number
      if (mobile.isEmpty || mobile.length < 10) {
        print('[CUSTOM OTP] Invalid mobile number: $mobile');
        return {
          'success': false,
          'message': 'Invalid mobile number',
        };
      }

      final normalizedMobile = mobile.replaceAll(RegExp(r'\D'), '');
      if (normalizedMobile == _testMobile) {
        print('[TEST_LOGIN] Test number detected');
        _currentOtp = _testOtp;
        _currentMobile = normalizedMobile;
        _otpExpiryTime = DateTime.now().add(_otpExpiryDuration);
        return {
          'success': true,
          'message': 'OTP sent successfully',
          'otp': _testOtp,
        };
      }

      print('[TEST_LOGIN] Normal OTP flow');
      
      // Generate new OTP
      final otp = _generateOtp();
      _currentOtp = otp;
      _currentMobile = mobile;
      _otpExpiryTime = DateTime.now().add(_otpExpiryDuration);
      
      print('[CUSTOM OTP] Generated OTP: $otp');
      print('[CUSTOM OTP] OTP Expiry Time: $_otpExpiryTime');
      
      // Format mobile number (add +91 prefix if not present)
      String formattedMobile = mobile;
      if (!mobile.startsWith('+')) {
        formattedMobile = '+91$mobile';
      }
      
      // Remove +91 for API (API expects 91 prefix without +)
      String apiMobile = formattedMobile.replaceAll('+', '');
      
      // Construct SMS message with App Signature Hash for auto-read
      // The hash MUST be at the end of the message for SMS Retriever API to work
      // Format: OTP followed by hash on separate line
      final smsMessage = 'Your ViteVikle Driver OTP is $otp\nu0czD5XQ8R/';
      
      // Call SMS API
      final url = '$_apiUrl?authkey=$_authKey&mobile=$apiMobile&otp=$otp&message=${Uri.encodeComponent(smsMessage)}';
      print('[CUSTOM OTP] API Request: $url');
      print('[CUSTOM OTP] SMS Message: $smsMessage');
      print('[CUSTOM OTP] App Signature Hash: $_appSignatureHash');
      
      final response = await _dio.get(
        url,
        options: Options(
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      
      print('[CUSTOM OTP] =========================================');
      print('[CUSTOM OTP] API RESPONSE DETAILS');
      print('[CUSTOM OTP] =========================================');
      print('[CUSTOM OTP] Response Status: ${response.statusCode}');
      print('[CUSTOM OTP] Response Status Code: ${response.statusMessage}');
      print('[CUSTOM OTP] Response Headers: ${response.headers}');
      print('[CUSTOM OTP] Response Data Type: ${response.data.runtimeType}');
      print('[CUSTOM OTP] Response Data: ${response.data}');
      print('[CUSTOM OTP] Response Data String: ${response.data.toString()}');
      print('[CUSTOM OTP] =========================================');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        print('[CUSTOM OTP] OTP sent successfully');
        return {
          'success': true,
          'message': 'OTP sent successfully',
          'otp': otp, // For testing purposes only
        };
      } else {
        print('[CUSTOM OTP] OTP send failed: ${response.data}');
        return {
          'success': false,
          'message': 'Failed to send OTP. Please try again.',
        };
      }
    } on DioException catch (e) {
      print('[CUSTOM OTP] Dio Exception: ${e.message}');
      print('[CUSTOM OTP] Dio Error Type: ${e.type}');
      print('[CUSTOM OTP] Dio Response: ${e.response}');
      
      String errorMessage = 'Network error. Please check your connection.';
      if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Connection timeout. Please try again.';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Server timeout. Please try again.';
      } else if (e.response != null) {
        errorMessage = 'Server error: ${e.response?.statusCode}';
      }
      
      return {
        'success': false,
        'message': errorMessage,
      };
    } catch (e) {
      print('[CUSTOM OTP] Exception: $e');
      return {
        'success': false,
        'message': 'An error occurred. Please try again.',
      };
    }
  }
  
  /// Verify the entered OTP
  Future<Map<String, dynamic>> verifyOtp({
    required String mobile,
    required String otp,
  }) async {
    try {
      print('[CUSTOM OTP] Verifying OTP for mobile: $mobile');
      print('[CUSTOM OTP] Entered OTP: $otp');
      print('[CUSTOM OTP] Stored OTP: $_currentOtp');
      print('[CUSTOM OTP] Stored Mobile: $_currentMobile');

      final normalizedMobile = mobile.replaceAll(RegExp(r'\D'), '');
      if (normalizedMobile == _testMobile) {
        if (otp == _testOtp) {
          print('[TEST_LOGIN] Test OTP accepted');
          _currentOtp = null;
          _currentMobile = null;
          _otpExpiryTime = null;
          return {
            'success': true,
            'message': 'OTP verified successfully',
          };
        }
        return {
          'success': false,
          'message': 'Invalid OTP',
        };
      }

      print('[TEST_LOGIN] Normal OTP flow');
      
      // Check if OTP has expired
      if (_otpExpiryTime != null && DateTime.now().isAfter(_otpExpiryTime!)) {
        print('[CUSTOM OTP] OTP has expired');
        return {
          'success': false,
          'message': 'OTP has expired. Please request a new OTP.',
        };
      }
      
      // Check if OTP matches
      if (_currentOtp == null || _currentMobile == null) {
        print('[CUSTOM OTP] No OTP found. Please request a new OTP.');
        return {
          'success': false,
          'message': 'No OTP found. Please request a new OTP.',
        };
      }
      
      // Verify mobile number matches
      if (_currentMobile != mobile) {
        print('[CUSTOM OTP] Mobile number mismatch');
        return {
          'success': false,
          'message': 'Mobile number mismatch. Please request a new OTP.',
        };
      }
      
      // Verify OTP
      if (_currentOtp == otp) {
        print('[CUSTOM OTP] OTP verified successfully');
        // Clear OTP after successful verification
        _currentOtp = null;
        _currentMobile = null;
        _otpExpiryTime = null;
        return {
          'success': true,
          'message': 'OTP verified successfully',
        };
      } else {
        print('[CUSTOM OTP] Invalid OTP');
        return {
          'success': false,
          'message': 'Invalid OTP. Please try again.',
        };
      }
    } catch (e) {
      print('[CUSTOM OTP] Verification Exception: $e');
      return {
        'success': false,
        'message': 'An error occurred during verification.',
      };
    }
  }
  
  /// Clear stored OTP
  void clearOtp() {
    print('[CUSTOM OTP] Clearing stored OTP');
    _currentOtp = null;
    _currentMobile = null;
    _otpExpiryTime = null;
  }
  
  /// Get remaining OTP expiry time in seconds
  int? getRemainingExpirySeconds() {
    if (_otpExpiryTime == null) return null;
    final remaining = _otpExpiryTime!.difference(DateTime.now());
    return remaining.inSeconds > 0 ? remaining.inSeconds : 0;
  }
}

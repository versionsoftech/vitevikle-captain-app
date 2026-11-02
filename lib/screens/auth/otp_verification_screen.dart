import 'dart:async';
import 'dart:io';
import 'package:vite_captain/widgets/vite_loader.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:smart_auth/smart_auth.dart';
import 'package:vite_captain/providers/auth_provider.dart' as app_auth;
import 'package:vite_captain/providers/driver_auth_provider.dart';
import 'package:vite_captain/services/firebase_auth_service.dart';
import 'package:vite_captain/services/custom_otp_service.dart';

// FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
// This screen now uses CustomOtpService instead of Firebase Phone Authentication
// All Firebase OTP methods have been commented out but preserved for potential future use

// OTP AUTO-READ IMPLEMENTATION
// Uses SMS User Consent API (smart_auth) to automatically detect and fill OTP from SMS
// SMS User Consent API does NOT require App Signature Hash
// Works with DLT SMS templates

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.mobile,
    this.verificationId,
    this.resendToken,
    this.autoCredential,
    this.useCustomOtp = false,
  });

  final String mobile;
  final String? verificationId;
  final int? resendToken;
  final PhoneAuthCredential? autoCredential;
  final bool useCustomOtp;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const Color primaryGreen = Color(0xFF009640);
  static const Color buttonGreen = Color(0xFF009640);
  static const Color inputBg = Color(0xFFF1F1F1);

  static const int _initialSeconds = 3;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  Timer? _timer;
  int _secondsLeft = _initialSeconds;

  bool _isVerifying = false;
  bool _manualAllowed = false;

  StreamSubscription<PhoneAuthCredential>? _autoSub;

  String? _verificationId;
  int? _resendToken;
  bool _autoWaitingSnackShown = false;

  // OTP Auto-Read Variables
  // SMS User Consent API - Does NOT require App Signature Hash
  String? _smsCode;
  bool _otpAutoFilled = false;

  static const String _testMobile = '9876543210';
  static const String _testOtp = '123456';

  String get _displayMobile => widget.mobile.trim();
  bool get _isTestLogin => widget.mobile.replaceAll(RegExp(r'\D'), '') == _testMobile;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _waitingAutoWidget() {
    if (_manualAllowed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: const [
          Text(
            'Waiting for automatic OTP verification...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 10),
          SizedBox(
            height: 20,
            width: 20,
            child: ViteLoader(strokeWidth: 2.2),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
    _focusNodes = List.generate(6, (_) => FocusNode());

    if (_isTestLogin) {
      print('[TEST_LOGIN] Test number detected');
      setState(() {
        _manualAllowed = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        print('[TEST_LOGIN] Auto filling OTP');
        _autoFillOtp(_testOtp);
      });
      return;
    }

    _startTimer();

    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;

    // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
    // _autoSub = FirebaseAuthService.instance.autoCredentialStream.listen((credential) {
    //   if (!mounted) return;
    //   if (_isVerifying) return;
    //   _completeWithCredential(credential);
    // });

    // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   final c = widget.autoCredential ?? FirebaseAuthService.instance.consumeAutoCredential();
    //   if (c != null) {
    //     _completeWithCredential(c);
    //   }
    // });

    // CUSTOM OTP: Enable manual input immediately (no auto-verification)
    if (widget.useCustomOtp) {
      print('[OTP SCREEN] Using custom OTP - manual input enabled');
      setState(() {
        _manualAllowed = true;
      });
      
      // Initialize SMS User Consent API
      _initSmsUserConsent();
    }
  }

  // SMS User Consent API Implementation
  void _initSmsUserConsent() async {
    if (!Platform.isAndroid) return;
    print('[OTP USER CONSENT] =========================================');
    print('[OTP USER CONSENT] INITIALIZING SMS USER CONSENT API');
    print('[OTP USER CONSENT] =========================================');
    
    try {
      final smartAuth = SmartAuth.instance;
      
      print('[OTP USER CONSENT] Requesting SMS User Consent...');
      final res = await smartAuth.getSmsWithUserConsentApi();
      
      if (res.hasData) {
        print('[OTP USER CONSENT] SMS RECEIVED WITH CONSENT');
        print('[OTP USER CONSENT] Result: $res');
        
        final code = res.requireData.code;
        print('[OTP USER CONSENT] SMS Code: $code');
        
        if (!mounted) {
          print('[OTP USER CONSENT] Widget not mounted, ignoring');
          return;
        }
        
        // The code can be null if the SMS was received but the code was not extracted
        if (code == null) {
          print('[OTP USER CONSENT] Code is null, cannot extract OTP');
        } else {
          print('[OTP USER CONSENT] Code extracted directly: $code');
          // Extract 6-digit OTP from the code (might be the full SMS or just the OTP)
          final otp = _extractOtpFromSms(code);
          if (otp != null && otp.length == 6) {
            print('[OTP USER CONSENT] Valid OTP found, auto-filling...');
            _autoFillOtp(otp);
          } else {
            print('[OTP USER CONSENT] Failed to extract valid OTP from code');
          }
        }
      } else if (res.isCanceled) {
        print('[OTP USER CONSENT] User canceled consent');
      } else {
        print('[OTP USER CONSENT] SMS User Consent failed: $res');
      }
      
      print('[OTP USER CONSENT] =========================================');
    } catch (e) {
      print('[OTP USER CONSENT] =========================================');
      print('[OTP USER CONSENT] FAILED TO INITIALIZE SMS USER CONSENT');
      print('[OTP USER CONSENT] Error: $e');
      print('[OTP USER CONSENT] =========================================');
    }
  }

  // SMS Retriever API NOT SUPPORTED - DLT template cannot be modified
  // Using Autofill Hint as fallback instead
  // This code is kept for reference if DLT template is ever modified

  // OTP Auto-Read Implementation (DISABLED - DLT template issue)
  // void _initSmsAutoFill() async {
  //   print('[OTP AUTO-READ] =========================================');
  //   print('[OTP AUTO-READ] INITIALIZING SMS AUTO-FILL LISTENER');
  //   print('[OTP AUTO-READ] =========================================');
  //   
  //   try {
  //     print('[OTP AUTO-READ] Calling SmsAutoFill().listenForCode()...');
  //     await SmsAutoFill().listenForCode();
  //     print('[OTP AUTO-READ] listenForCode() completed successfully');
  //     
  //     print('[OTP AUTO-READ] Subscribing to SmsAutoFill().code stream...');
  //     _smsSubscription = SmsAutoFill().code.listen(
  //       (String code) {
  //         print('[OTP AUTO-READ] =========================================');
  //         print('[OTP AUTO-READ] SMS RECEIVED!');
  //         print('[OTP AUTO-READ] Raw Code: $code');
  //         print('[OTP AUTO-READ] =========================================');
  //         
  //         if (!mounted) {
  //           print('[OTP AUTO-READ] Widget not mounted, ignoring');
  //           return;
  //         }
  //         
  //         final otp = _extractOtpFromSms(code);
  //         print('[OTP AUTO-READ] Extracted OTP: $otp');
  //         
  //         if (otp != null && otp.length == 6) {
  //           print('[OTP AUTO-READ] Valid OTP found, auto-filling...');
  //           _autoFillOtp(otp);
  //         } else {
  //           print('[OTP AUTO-READ] Failed to extract valid OTP from SMS');
  //           print('[OTP AUTO-READ] SMS content: $code');
  //         }
  //       },
  //       onError: (error) {
  //         print('[OTP AUTO-READ] =========================================');
  //         print('[OTP AUTO-READ] SMS LISTENER ERROR: $error');
  //         print('[OTP AUTO-READ] =========================================');
  //       },
  //       onDone: () {
  //         print('[OTP AUTO-READ] SMS listener stream completed');
  //       },
  //     );
  //     
  //     print('[OTP AUTO-READ] SMS listener subscription created successfully');
  //     print('[OTP AUTO-READ] SMS listener is now ACTIVE and waiting for SMS');
  //     print('[OTP AUTO-READ] =========================================');
  //     
  //   } catch (e) {
  //     print('[OTP AUTO-READ] =========================================');
  //     print('[OTP AUTO-READ] FAILED TO INITIALIZE SMS LISTENER');
  //     print('[OTP AUTO-READ] Error: $e');
  //     print('[OTP AUTO-READ] =========================================');
  //   }
  // }

  String? _extractOtpFromSms(String sms) {
    print('[OTP USER CONSENT] Extracting OTP from SMS: $sms');
    
    // Try to find 6-digit OTP in the SMS
    // Works with DLT template: "848622 is your OTP for Verification. - APIIND"
    final otpRegex = RegExp(r'\b\d{6}\b');
    final match = otpRegex.firstMatch(sms);
    
    if (match != null) {
      final otp = match.group(0);
      print('[OTP USER CONSENT] Found OTP: $otp');
      return otp;
    }
    
    print('[OTP USER CONSENT] No 6-digit OTP found in SMS');
    return null;
  }

  void _autoFillOtp(String otp) {
    print('[OTP USER CONSENT] =========================================');
    print('[OTP USER CONSENT] AUTO-FILLING OTP: $otp');
    print('[OTP USER CONSENT] =========================================');
    
    if (_otpAutoFilled) {
      print('[OTP USER CONSENT] OTP already auto-filled, skipping');
      return;
    }
    
    // Fill each OTP field
    for (int i = 0; i < 6 && i < otp.length; i++) {
      _controllers[i].text = otp[i];
      print('[OTP USER CONSENT] Filled field $i with digit ${otp[i]}');
    }
    
    setState(() {
      _otpAutoFilled = true;
    });
    
    print('[OTP USER CONSENT] OTP auto-filled successfully');
    print('[OTP USER CONSENT] =========================================');
    
    // Auto-submit OTP after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _otpAutoFilled) {
        print('[OTP USER CONSENT] Auto-submitting OTP...');
        _verify();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
    // _autoSub?.cancel();
    
    if (Platform.isAndroid) {
      SmartAuth.instance.removeUserConsentApiListener();
    }
    
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = _initialSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        setState(() {
          _secondsLeft = 0;
          _manualAllowed = true;
        });
        t.cancel();
      } else {
        setState(() {
          _secondsLeft -= 1;
        });
      }
    });
  }

  bool get _canResend => _secondsLeft == 0;

  String get _formattedTime {
    final minutes = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _onOtpChanged(int index, String value) {
    if (value.isEmpty) {
      if (index > 0) {
        FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
        _controllers[index - 1].selection = TextSelection.fromPosition(
          TextPosition(offset: _controllers[index - 1].text.length),
        );
      }
      return;
    }

    final v = value.trim();
    if (v.length > 1) {
      _controllers[index].text = v.substring(v.length - 1);
      _controllers[index].selection = TextSelection.fromPosition(
        TextPosition(offset: _controllers[index].text.length),
      );
    }

    if (index < 5) {
      FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
    } else {
      FocusScope.of(context).unfocus();
      
      // Auto-submit when all 6 digits are filled
      final otp = _controllers.map((c) => c.text.trim()).join();
      if (otp.length == 6) {
        print('[OTP SCREEN] All 6 digits filled, auto-submitting...');
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _verify();
          }
        });
      }
    }
  }

  Widget _otpBox(int index) {
    return SizedBox(
      width: 50,
      height: 55,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        enabled: _manualAllowed,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        autofillHints: index == 0 ? [AutofillHints.oneTimeCode] : null,
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryGreen, width: 2),
          ),
        ),
        onChanged: (v) => _onOtpChanged(index, v),
      ),
    );
  }

  void _verify() {
    if (!_manualAllowed) {
      if (!_autoWaitingSnackShown) {
        _autoWaitingSnackShown = true;
        _showSnack('Waiting for automatic OTP verification...');
      }
      return;
    }

    final otp = _controllers.map((c) => c.text.trim()).join();
    if (otp.length != 6) {
      _showSnack('Please enter valid OTP');
      return;
    }

    if (widget.useCustomOtp) {
      // CUSTOM OTP IMPLEMENTATION
      print('[OTP SCREEN] Verifying custom OTP');
      _verifyCustomOtp(otp);
    } else {
      // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
      // if (_verificationId == null) {
      //   _showSnack('Please resend OTP');
      //   return;
      // }
      // final credential = FirebaseAuthService.instance.credentialFromSms(
      //   verificationId: _verificationId!,
      //   smsCode: otp,
      // );
      // _completeWithCredential(credential);
      _showSnack('Please use custom OTP');
    }
  }

  Future<void> _verifyCustomOtp(String otp) async {
    setState(() {
      _isVerifying = true;
    });

    print('[OTP SCREEN] Verifying OTP: $otp for mobile: ${widget.mobile}');

    final result = await CustomOtpService.instance.verifyOtp(
      mobile: widget.mobile,
      otp: otp,
    );

    print('[OTP SCREEN] Custom OTP verification result: $result');

    if (!mounted) return;
    setState(() {
      _isVerifying = false;
    });

    if (result['success'] == true) {
      print('[OTP SCREEN] OTP verified successfully, proceeding to login');
      if (_isTestLogin) {
        print('[TEST_LOGIN] OTP verified');
      }
      await _completeLogin();
    } else {
      print('[OTP SCREEN] OTP verification failed: ${result['message']}');
      _showSnack(result['message'] ?? 'Invalid OTP');
    }
  }

  Future<void> _completeLogin() async {
    setState(() {
      _isVerifying = true;
    });

    try {
      final result = await context.read<DriverAuthProvider>().login(widget.mobile);
      print('[OTP SCREEN] Driver login result: $result');

      if (!mounted) return;
      setState(() {
        _isVerifying = false;
      });

      if (result['success'] != true) {
        _showSnack((result['message'] ?? 'Login failed').toString());
        return;
      }

      if (_isTestLogin) {
        print('[TEST_LOGIN] Login success');
      }

      await context.read<app_auth.AuthProvider>().handleDriverStatusRouting(
            context: context,
            mobile: widget.mobile,
            result: result,
            replaceAll: true,
          );

      final err = context.read<app_auth.AuthProvider>().error;
      if (err != null && err.trim().isNotEmpty) {
        _showSnack(err);
        context.read<app_auth.AuthProvider>().clearError();
      }
    } catch (e) {
      print('[OTP SCREEN] Login exception: $e');
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
      });
      _showSnack('Login failed. Please try again.');
    }
  }

  void _resend() {
    if (!_canResend) return;
    for (final c in _controllers) {
      c.clear();
    }
    FocusScope.of(context).requestFocus(_focusNodes.first);
    _startTimer();

    setState(() {
      _manualAllowed = false;
      _isVerifying = false;
      _otpAutoFilled = false; // Reset auto-fill state
    });

    if (widget.useCustomOtp) {
      // CUSTOM OTP IMPLEMENTATION
      print('[OTP SCREEN] Resending custom OTP');
      _resendCustomOtp();
    } else {
      // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
      // final phoneNumber = '+91${widget.mobile}';
      // FirebaseAuthService.instance.sendOtp(
      //   phoneNumber: phoneNumber,
      //   forceResendingToken: _resendToken,
      //   onCodeSent: (verificationId, resendToken) {
      //     if (!mounted) return;
      //     setState(() {
      //       _verificationId = verificationId;
      //       _resendToken = resendToken;
      //     });
      //   },
      //   onFailed: (message) {
      //     _showSnack(message);
      //   },
      //   onAutoVerified: (credential) {
      //     _completeWithCredential(credential);
      //   },
      //   onTimeout: (verificationId) {
      //     if (!mounted) return;
      //     setState(() {
      //       _verificationId = verificationId;
      //       _manualAllowed = true;
      //     });
      //   },
      // );
      _showSnack('Please use custom OTP');
    }
  }

  Future<void> _resendCustomOtp() async {
    setState(() {
      _isVerifying = true;
    });

    print('[OTP SCREEN] Resending OTP to mobile: ${widget.mobile}');

    final result = await CustomOtpService.instance.sendOtp(mobile: widget.mobile);

    print('[OTP SCREEN] Resend OTP result: $result');

    if (!mounted) return;
    setState(() {
      _isVerifying = false;
      _manualAllowed = true;
    });

    if (result['success'] == true) {
      print('[OTP SCREEN] OTP resent successfully');
      _showSnack('OTP resent successfully');
      
      // Reinitialize SMS User Consent for new OTP
      _initSmsUserConsent();
    } else {
      print('[OTP SCREEN] OTP resend failed: ${result['message']}');
      _showSnack(result['message'] ?? 'Failed to resend OTP');
    }
  }

  // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
  // Future<void> _completeWithCredential(PhoneAuthCredential credential) async {
  //   if (_isVerifying) return;
  //   setState(() {
  //     _isVerifying = true;
  //   });

  //   final result = await context.read<app_auth.AuthProvider>().verifyOtpAndLogin(
  //         context: context,
  //         credential: credential,
  //         mobile: widget.mobile,
  //       );
  //   if (!mounted) return;

  //   setState(() {
  //     _isVerifying = false;
  //   });

  //   if (result['success'] != true) {
  //     _showSnack((result['message'] ?? 'Something went wrong').toString());
  //     return;
  //   }

  //   // Stop listening to any further auto-verification events once successful
  //   try {
  //     await _autoSub?.cancel();
  //   } catch (_) {}

  //   await context.read<app_auth.AuthProvider>().handleDriverStatusRouting(
  //         context: context,
  //         mobile: widget.mobile,
  //         result: result,
  //         replaceAll: true,
  //       );

  //   final err = context.read<app_auth.AuthProvider>().error;
  //   if (err != null && err.trim().isNotEmpty) {
  //     _showSnack(err);
  //     context.read<app_auth.AuthProvider>().clearError();
  //   }
  // }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (!keyboardOpen) return;

    if (_manualAllowed) return;

    // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
    // Future.microtask(() {
    //   if (!mounted) return;
    //   if (_manualAllowed) return;
    //   if (!_autoWaitingSnackShown) {
    //     _autoWaitingSnackShown = true;
    //     _showSnack('Waiting for OTP auto verification...');
    //   }
    // });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    final double expandedHeaderHeight = media.size.height * 0.36;
    final double headerHeight = keyboardOpen ? 0 : expandedHeaderHeight;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        left: false,
        right: false,
        bottom: false,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOut,
              height: headerHeight,
              width: double.infinity,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                opacity: keyboardOpen ? 0 : 1,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOut,
                  offset: keyboardOpen ? const Offset(0, -0.15) : Offset.zero,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(40),
                      bottomRight: Radius.circular(40),
                    ),
                    child: Image.asset(
                      'assets/images/otp_verification/otp.png',
                      width: double.infinity,
                      height: expandedHeaderHeight,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: media.viewInsets.bottom + media.padding.bottom + 10,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 22),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_user, color: primaryGreen),
                          SizedBox(width: 8),
                          Text(
                            'OTP Verification',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Enter the 6-digit code sent to $_displayMobile',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, _otpBox),
                      ),
                      _waitingAutoWidget(),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          onPressed: (_isVerifying || !_manualAllowed) ? null : _verify,
                          child: const Text(
                            'Verify',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        "Didn't receive the code?",
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black54,
                        ),
                      ),
                      TextButton(
                        onPressed: _canResend ? _resend : null,
                        child: const Text(
                          'Resend OTP',
                          style: TextStyle(
                            color: primaryGreen,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        'Re-send code in $_formattedTime',
                        style: TextStyle(
                          fontSize: 14,
                          color: _canResend ? Colors.black54 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


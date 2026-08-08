import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/providers/auth_provider.dart' as app_auth;
import 'package:vite_captain/providers/driver_auth_provider.dart';
import 'package:vite_captain/screens/map_screen.dart';
import 'package:vite_captain/screens/first_launch_flow_screen.dart';
import 'package:vite_captain/screens/auth/otp_verification_screen.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/custom_otp_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.openSignUp = false,
    this.prefillMobile,
    this.lockMobile = false,
  });

  final bool openSignUp;
  final String? prefillMobile;
  final bool lockMobile;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {

  static const Color primaryGreen = Color(0xFF0FA958);
  static const Color darkGreen = Color(0xFF369D01);
  static const Color inputFillGrey = Color(0xFFF1F1F1);
  static const Color inactiveTabText = Color(0xFF6B7280);

  late final TabController _tabController;

  bool _usePasswordSignIn = false;
  bool _isSigningIn = false;
  bool _isRegistering = false;
  bool _isSendingOtp = false;

  bool _lockSignUpMobile = false;

  final TextEditingController _signInEmailOrMobileController = TextEditingController();
  final TextEditingController _signInPasswordController = TextEditingController();

  final TextEditingController _signUpFullNameController = TextEditingController();
  final TextEditingController _signUpEmailController = TextEditingController();
  final TextEditingController _signUpMobileController = TextEditingController();
  final TextEditingController _signUpReferenceCodeController = TextEditingController();

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handlePasswordSignIn() async {
    _showSnack('Password login is not available. Please use OTP.');
  }

  Future<void> _handleSendOtp() async {
    final raw = _signInEmailOrMobileController.text.trim();
    final mobile = raw.replaceAll(RegExp(r'\D'), '');

    if (mobile.isEmpty || mobile.length < 10) {
      _showSnack('Please enter valid mobile number');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSendingOtp = true;
    });

    print('[LOGIN SCREEN] Sending OTP to mobile: $mobile');

    try {
      // FIREBASE OTP DISABLED - KEPT FOR FUTURE USE
      // await FirebaseAuth.instance.verifyPhoneNumber(
      //   phoneNumber: phoneNumber,
      //   verificationCompleted: (PhoneAuthCredential credential) async {
      //     print('AUTO VERIFIED');
      //     try {
      //       await FirebaseAuth.instance.signInWithCredential(credential);
      //       if (!mounted) return;
      //       setState(() {
      //         _isSendingOtp = false;
      //       });
      //       final result = await context.read<DriverAuthProvider>().login(mobile);
      //       if (!mounted) return;
      //       if (result['success'] == true) {
      //         await context.read<app_auth.AuthProvider>().handleDriverStatusRouting(
      //               context: context,
      //               mobile: mobile,
      //               result: result,
      //               replaceAll: true,
      //             );
      //         return;
      //       }
      //       _showSnack((result['message'] ?? 'Login failed').toString());
      //     } catch (e) {
      //       if (!mounted) return;
      //       setState(() {
      //         _isSendingOtp = false;
      //       });
      //       _showSnack('Auto verification failed');
      //     }
      //   },
      //   verificationFailed: (FirebaseAuthException e) {
      //     print('VERIFICATION FAILED');
      //     print('VERIFICATION FAILED -> code=${e.code} message=${e.message}');
      //     if (!mounted) return;
      //     setState(() {
      //       _isSendingOtp = false;
      //     });
      //     final code = e.code;
      //     if (code == 'invalid-phone-number') {
      //       _showSnack('Invalid number');
      //       return;
      //     }
      //     final msg = (e.message != null && e.message!.trim().isNotEmpty)
      //         ? e.message!.trim()
      //         : e.code;
      //     _showSnack(msg);
      //   },
      //   codeSent: (String verificationId, int? resendToken) {
      //     print('OTP SENT');
      //     print('OTP SENT -> verificationId=$verificationId resendToken=$resendToken');
      //     if (!mounted) return;
      //     setState(() {
      //       _isSendingOtp = false;
      //     });
      //     Navigator.push(
      //       context,
      //       MaterialPageRoute(
      //         builder: (context) => OtpVerificationScreen(
      //           mobile: mobile,
      //           verificationId: verificationId,
      //           resendToken: resendToken,
      //         ),
      //       ),
      //     );
      //   },
      //   codeAutoRetrievalTimeout: (String verificationId) {},
      // );

      // CUSTOM OTP IMPLEMENTATION
      final result = await CustomOtpService.instance.sendOtp(mobile: mobile);
      
      print('[LOGIN SCREEN] Custom OTP Result: $result');
      
      if (!mounted) return;
      setState(() {
        _isSendingOtp = false;
      });

      if (result['success'] == true) {
        print('[LOGIN SCREEN] OTP sent successfully');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpVerificationScreen(
              mobile: mobile,
              useCustomOtp: true,
            ),
          ),
        );
      } else {
        print('[LOGIN SCREEN] OTP send failed: ${result['message']}');
        _showSnack(result['message'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      print('[LOGIN SCREEN] OTP REQUEST EXCEPTION -> $e');
      if (!mounted) return;
      setState(() {
        _isSendingOtp = false;
      });
      _showSnack(e.toString());
    }
  }

  Future<void> _handleRegister() async {
    final name = _signUpFullNameController.text.trim();
    final email = _signUpEmailController.text.trim();
    final mobile = _signUpMobileController.text.trim();
    final referenceCode = _signUpReferenceCodeController.text.trim();

    if (name.isEmpty) {
      _showSnack('Please enter full name');
      return;
    }

    if (email.isEmpty) {
      _showSnack('Please enter email');
      return;
    }

    if (mobile.isEmpty) {
      _showSnack('Please enter mobile number');
      return;
    }

    setState(() {
      _isRegistering = true;
    });

    final response = await ApiService().registerUser(
      name: name,
      email: email,
      mobile: mobile,
      referenceCode: referenceCode,
    );

    if (!mounted) return;
    setState(() {
      _isRegistering = false;
    });

    final success = response['success'] == true;
    if (!success) {
      _showSnack((response['message'] ?? 'Registration failed').toString());
      return;
    }

    final token = response['token'];
    if (token is String && token.isNotEmpty) {
      await SessionService().saveLoginSession(
        token: token,
        mobile: mobile,
      );
    }

    _showSnack((response['message'] ?? 'Registered successfully').toString());

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const FirstLaunchFlowScreen(next: MapScreen())),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.openSignUp ? 1 : 0,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    if (widget.prefillMobile != null && widget.prefillMobile!.trim().isNotEmpty) {
      final m = widget.prefillMobile!.trim();
      _signUpMobileController.text = m;
      _signInEmailOrMobileController.text = m;
    }
    _lockSignUpMobile = widget.lockMobile;
  }

  @override
  void dispose() {
    _tabController.dispose();

    _signInEmailOrMobileController.dispose();
    _signInPasswordController.dispose();

    _signUpFullNameController.dispose();
    _signUpEmailController.dispose();
    _signUpMobileController.dispose();
    _signUpReferenceCodeController.dispose();

    super.dispose();
  }

  String get _headerImageAsset {
    if (_tabController.index == 1) {
      return 'assets/images/signin_signup/signup.png';
    }
    return 'assets/images/signin_signup/signin.png';
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: inputFillGrey,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
    bool isLoading = false,
    bool enabled = true,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _signInForm() {
    return Column(
      children: [
        TextField(
          controller: _signInEmailOrMobileController,
          decoration: _inputDecoration('Email / Mobile'),
        ),

        if (_usePasswordSignIn) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _signInPasswordController,
            obscureText: true,
            decoration: _inputDecoration('Password'),
          ),
        ],

        const SizedBox(height: 6),

        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              setState(() {
                _usePasswordSignIn = false;
              });
              _showSnack('Password login is not available. Please use OTP.');
            },
            child: Text(
              _usePasswordSignIn
                  ? 'Signin with OTP?'
                  : 'Signin with Password?',
              style: const TextStyle(
                color: darkGreen,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),

        _primaryButton(
          label: _usePasswordSignIn ? 'Sign In' : 'Get OTP',
          isLoading: _isSendingOtp,
          enabled: !_isSendingOtp,
          onPressed: () {
            if (_isSendingOtp) return;
            _handleSendOtp();
          },
        ),
      ],
    );
  }

  Widget _signUpForm() {
    return Column(
      children: [
        TextField(
          controller: _signUpFullNameController,
          decoration: _inputDecoration('Full Name'),
        ),

        const SizedBox(height: 8),

        TextField(
          controller: _signUpEmailController,
          decoration: _inputDecoration('Email'),
        ),

        const SizedBox(height: 8),

        TextField(
          controller: _signUpMobileController,
          enabled: !_lockSignUpMobile,
          decoration: _inputDecoration('Mobile'),
        ),

        const SizedBox(height: 8),

        TextField(
          controller: _signUpReferenceCodeController,
          decoration: _inputDecoration('Reference Code'),
        ),

        const SizedBox(height: 14),

        _primaryButton(
          label: 'Create Account',
          isLoading: _isRegistering,
          enabled: !_isRegistering,
          onPressed: () {
            if (_isRegistering) return;
            _handleRegister();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    final double expandedHeaderHeight = media.size.height * 0.36;
    final double headerHeight = keyboardOpen ? 0 : expandedHeaderHeight;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
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
                      _headerImageAsset,
                      width: double.infinity,
                      height: expandedHeaderHeight,
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: [
                    const SizedBox(height: 12),

                    /// TABS
                    TabBar(
                      controller: _tabController,
                      indicatorColor: darkGreen,
                      indicatorWeight: 3,
                      labelColor: darkGreen,
                      unselectedLabelColor: inactiveTabText,
                      labelStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      tabs: const [
                        Tab(text: 'Sign In'),
                        Tab(text: 'Sign Up'),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [

                          /// SIGN IN
                          SingleChildScrollView(
                            padding: EdgeInsets.only(
                              bottom: media.viewInsets.bottom + 16,
                            ),
                            child: Column(
                              children: [
                                _signInForm(),
                                const SizedBox(height: 14),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text(
                                    "Skip",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          /// SIGN UP
                          SingleChildScrollView(
                            padding: EdgeInsets.only(
                              bottom: media.viewInsets.bottom + 16,
                            ),
                            child: Column(
                              children: [
                                _signUpForm(),
                                const SizedBox(height: 14),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text(
                                    "Skip",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vite_captain/services/session_service.dart';

class FirstLaunchFlowScreen extends StatefulWidget {
  const FirstLaunchFlowScreen({
    super.key,
    required this.next,
  });

  final Widget next;

  @override
  State<FirstLaunchFlowScreen> createState() => _FirstLaunchFlowScreenState();
}

class _FirstLaunchFlowScreenState extends State<FirstLaunchFlowScreen> {
  static const Color _greenA = Color(0xFF16A34A);
  static const Color _greenB = Color(0xFF22C55E);

  bool _checking = true;

  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrate();
    });
  }

  Future<void> _hydrate() async {
    try {
      final accepted = await const SessionService().getDisclaimerAccepted();
      final locationGranted = await const SessionService().getLocationPermissionGranted();
      if (!mounted) return;
      if (accepted && locationGranted) {
        await _ensureLocationPermission(fetchLocation: false);
        return;
      }

      setState(() {
        _checking = false;
      });

      if (accepted) {
        await _ensureLocationPermission(fetchLocation: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
      });
    }
  }

  Future<void> _ensureLocationPermission({required bool fetchLocation}) async {
    if (!mounted) return;

    final status = await Permission.locationWhenInUse.status;
    if (status.isGranted) {
      await const SessionService().setLocationPermissionGranted(true);
      if (fetchLocation) {
        await _fetchCurrentLocationOrOpenSettings();
      }
      await _enterApp();
      return;
    }

    final req = await Permission.locationWhenInUse.request();
    if (req.isGranted) {
      await const SessionService().setLocationPermissionGranted(true);
      if (fetchLocation) {
        await _fetchCurrentLocationOrOpenSettings();
      }
      await _enterApp();
      return;
    }

    if (req.isPermanentlyDenied || req.isRestricted) {
      try {
        await openAppSettings();
      } catch (_) {}
    }
  }

  Future<void> _fetchCurrentLocationOrOpenSettings() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        try {
          await Geolocator.openLocationSettings();
        } catch (_) {}
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      // ignore: unused_local_variable
      final _ = pos;
    } catch (_) {
      // ignore
    }
  }

  Future<void> _enterApp() async {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => widget.next),
      (route) => false,
    );
  }

  Future<void> _acceptDisclaimer() async {
    if (_requesting) return;

    setState(() {
      _requesting = true;
    });

    try {
      await const SessionService().setDisclaimerAccepted(true);
      if (!mounted) return;
      await _ensureLocationPermission(fetchLocation: true);
    } finally {
      if (mounted) {
        setState(() {
          _requesting = false;
        });
      }
    }
  }

  Widget _buildDisclaimerSection({
    required IconData icon,
    required String title,
    required String content,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800.withOpacity(0.5) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _greenA.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: _greenA,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.5,
              color: isDark ? Colors.grey.shade300 : Colors.black87,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientButton({
    required String text,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: onPressed == null
                ? [Colors.grey.shade300, Colors.grey.shade300]
                : const [_greenA, _greenB],
          ),
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onPressed,
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: onPressed == null ? Colors.black38 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 120,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_greenA, _greenB],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location Access Required',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Why we need your location',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Icon(
                          Icons.shield,
                          size: 48,
                          color: _greenA,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Welcome to ViteVikle',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Driver Terms & Guidelines',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildDisclaimerSection(
                        icon: Icons.security,
                        title: 'Safety & Responsibility',
                        content: 'By using the ViteVikle Driver App, you confirm that all information provided during registration and profile updates is accurate, complete, and up to date. You agree to operate your vehicle responsibly, prioritize passenger safety, obey all applicable traffic laws, and maintain professional behaviour while providing transportation or delivery services through the ViteVikle platform.',
                        theme: theme,
                      ),
                      const SizedBox(height: 16),
                      _buildDisclaimerSection(
                        icon: Icons.description,
                        title: 'Documents & Compliance',
                        content: 'You are solely responsible for ensuring that your driving licence, vehicle registration certificate (RC), insurance, pollution certificate (PUC), permits, identity proof, and any other required documents remain valid and updated at all times. Any expired, forged, inaccurate, or misleading document may result in suspension or permanent termination of your driver account.',
                        theme: theme,
                      ),
                      const SizedBox(height: 16),
                      _buildDisclaimerSection(
                        icon: Icons.directions_car,
                        title: 'Driver Conduct',
                        content: 'Drivers are expected to provide safe, respectful, and professional service to every passenger. Unsafe driving, abusive language, discrimination, intoxication, reckless behaviour, fraudulent bookings, fake GPS locations, ride manipulation, or any activity that negatively impacts customer safety or platform integrity is strictly prohibited.',
                        theme: theme,
                      ),
                      const SizedBox(height: 16),
                      _buildDisclaimerSection(
                        icon: Icons.lock,
                        title: 'Privacy & Account Security',
                        content: 'Your account is personal and must not be shared with any other individual. You are responsible for protecting your login credentials and all activities performed through your account. ViteVikle may monitor platform usage to improve security, prevent fraud, and ensure compliance with company policies.',
                        theme: theme,
                      ),
                      const SizedBox(height: 16),
                      _buildDisclaimerSection(
                        icon: Icons.gavel,
                        title: 'Terms & Policies',
                        content: 'By continuing to use this application, you agree to comply with the ViteVikle Terms & Conditions, Privacy Policy, Community Guidelines, Driver Policies, and all applicable local, state, and national laws. ViteVikle reserves the right to investigate policy violations and may suspend or permanently deactivate accounts that breach these terms.',
                        theme: theme,
                      ),
                      const SizedBox(height: 16),
                      _buildDisclaimerSection(
                        icon: Icons.check_circle,
                        title: 'Acknowledgement',
                        content: 'By continuing to use the ViteVikle Driver App, you acknowledge that you have carefully read, understood, and accepted this disclaimer. You agree to use the platform responsibly, maintain accurate information, comply with all legal and platform requirements, and understand that any misuse, fraudulent activity, policy violation, or illegal conduct may result in account suspension, permanent deactivation, legal action, or other measures deemed appropriate by ViteVikle.',
                        theme: theme,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _gradientButton(
                text: _requesting ? 'Please wait...' : 'Accept & Continue',
                onPressed: _requesting ? null : _acceptDisclaimer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


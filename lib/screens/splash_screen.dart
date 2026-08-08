import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/screens/auth/login_screen.dart';
import 'package:vite_captain/screens/home_screen.dart';
import 'package:vite_captain/screens/onboarding_screen.dart';
import 'package:vite_captain/screens/loader_screen.dart';
import 'package:vite_captain/screens/first_launch_flow_screen.dart';
import 'package:vite_captain/providers/driver_status_summary_provider.dart';
import 'package:vite_captain/services/local_storage_service.dart';
import 'package:vite_captain/services/app_config.dart';
import 'package:vite_captain/services/in_app_update_service.dart';

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  Route _noAnimRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startApp();
    });
  }

  Future<void> _startApp() async {
    const storage = LocalStorageService();

    await AppConfig.loadAppSettings();

    if (!mounted) return;
    final canContinue = await InAppUpdateService().gateAppStart(
      context,
      appType: 'driver',
    );
    if (!canContinue) return;

    final onboardingDone = await storage.getOnboardingCompleted();
    if (!mounted) return;

    if (!onboardingDone) {
      Navigator.pushReplacement(
        context,
        _noAnimRoute(const OnboardingScreen()),
      );
      return;
    }

    final isLoggedIn = await storage.getLoginStatus();
    if (!mounted) return;

    if (!isLoggedIn) {
      Navigator.pushReplacement(context, _noAnimRoute(const LoginScreen()));
      return;
    }

    await context.read<DriverStatusSummaryProvider>().refresh(silent: true);
    if (!mounted) return;

    final isVerified = await storage.getDriverIsVerified();
    final status = await storage.getDriverStatus();
    if (!mounted) return;

    if (isVerified && status == true) {
      Navigator.pushReplacement(
        context,
        _noAnimRoute(
          const FirstLaunchFlowScreen(next: HomeScreen()),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      _noAnimRoute(
        const FirstLaunchFlowScreen(next: LoaderScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF00A651)),
      ),
    );
  }
}

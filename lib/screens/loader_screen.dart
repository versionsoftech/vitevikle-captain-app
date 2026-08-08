import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/providers/auth_provider.dart';
import 'package:vite_captain/providers/driver_auth_provider.dart';
import 'package:vite_captain/screens/auth/login_screen.dart';
import 'package:vite_captain/services/local_storage_service.dart';

class LoaderScreen extends StatefulWidget {
  const LoaderScreen({super.key});

  @override
  State<LoaderScreen> createState() => _LoaderScreenState();
}

class _LoaderScreenState extends State<LoaderScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _check();
    });
  }

  Future<void> _check() async {
    const storage = LocalStorageService();

    final isLoggedIn = await storage.getLoginStatus();
    final mobile = (await storage.getMobile())?.trim() ?? '';

    if (!mounted) return;

    final hasSession = isLoggedIn && mobile.isNotEmpty;
    if (!hasSession) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }

    final result = await context.read<DriverAuthProvider>().login(mobile);
    if (!mounted) return;

    if (result['success'] == true) {
      await context.read<AuthProvider>().handleDriverStatusRouting(
            context: context,
            mobile: mobile,
            result: result,
            replaceAll: false,
          );
      return;
    }

    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}


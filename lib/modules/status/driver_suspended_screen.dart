import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DriverSuspendedScreen extends StatelessWidget {
  const DriverSuspendedScreen({super.key});

  static const String supportPhone = '9646006716';
  static const String supportEmail = 'vitevikle@gmail.com';

  Future<void> _open(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.pause_circle_filled_rounded, color: Color(0xFFD32F2F), size: 40),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Account suspended',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You cannot take rides until ViteVikle support turns this account back on.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => _open(Uri.parse('tel:$supportPhone')),
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('Call support'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF009640),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => _open(Uri.parse('mailto:$supportEmail')),
                        icon: const Icon(Icons.mail_outline_rounded),
                        label: const Text('Email support'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF007A34),
                          side: const BorderSide(color: Color(0xFF009640)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Support  •  9646006716  •  vitevikle@gmail.com',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

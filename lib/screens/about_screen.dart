import 'package:flutter/material.dart';
import 'package:vite_captain/screens/policy_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Widget _row(BuildContext context, {
    required String title,
    required String value,
    bool showArrow = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (showArrow)
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('About'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: _card(context,
            children: [
              _row(context, title: 'App name', value: 'ViteVikle'),
              Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
              _row(context, title: 'App version', value: '8.99.0'),
              Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
              _row(context, title: 'Company', value: 'ViteVikle', showArrow: false),
              Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
              _row(context, 
                title: 'Privacy Policy',
                value: 'View',
                showArrow: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PolicyScreen(type: 'privacy'),
                    ),
                  );
                },
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
              _row(context, 
                title: 'Terms & Conditions',
                value: 'View',
                showArrow: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PolicyScreen(type: 'terms'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


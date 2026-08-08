import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/providers/app_settings_provider.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }

  Card _card({required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: child,
    );
  }

  Future<void> _openLanguageSheet(AppSettingsProvider provider) async {
    final selected = provider.locale.languageCode;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        Widget item({required String code, required String label}) {
          final active = selected == code;
          return ListTile(
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: active ? const Icon(Icons.check_circle, color: Color(0xFF16A34A)) : null,
            onTap: () async {
              await provider.setLanguage(code);
              if (context.mounted) Navigator.pop(context);
            },
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose Language',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                item(code: 'en', label: 'English'),
                item(code: 'hi', label: 'Hindi'),
                item(code: 'pa', label: 'Punjabi'),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Consumer<AppSettingsProvider>(
      builder: (context, settings, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: AppBar(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            title: const Text('App Settings'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionTitle('Preferences'),
                  _card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0x1A16A34A),
                        child: Icon(Icons.language, color: Color(0xFF16A34A), size: 20),
                      ),
                      title: const Text('Change Language', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(settings.languageLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openLanguageSheet(settings),
                    ),
                  ),

                  // Dark Mode UI hidden as requested

                  _sectionTitle('Legal'),
                  _card(
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: const CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(0x1A16A34A),
                            child: Icon(Icons.privacy_tip_outlined, color: Color(0xFF16A34A), size: 20),
                          ),
                          title: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.w800)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pushNamed(context, '/privacy-policy'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: const CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(0x1A16A34A),
                            child: Icon(Icons.description_outlined, color: Color(0xFF16A34A), size: 20),
                          ),
                          title: const Text('Terms & Conditions', style: TextStyle(fontWeight: FontWeight.w800)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pushNamed(context, '/terms-condition'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


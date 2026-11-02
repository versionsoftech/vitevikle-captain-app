import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vite_captain/modules/registration/driver_license_screen.dart';

class PersonalPicturePreviewScreen extends StatefulWidget {
  const PersonalPicturePreviewScreen({
    super.key,
    required this.driverId,
    required this.mobile,
    required this.imagePath,
  });

  final String driverId;
  final String mobile;
  final String imagePath;

  @override
  State<PersonalPicturePreviewScreen> createState() => _PersonalPicturePreviewScreenState();
}

class _PersonalPicturePreviewScreenState extends State<PersonalPicturePreviewScreen> {
  static const Color _lightGreen = Color(0xFFB7E11A);

  bool _saving = false;
  String? _error;

  Future<void> _usePicture() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final dest = File('${tempDir.path}/personal_picture_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final saved = await File(widget.imagePath).copy(dest.path);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverLicenseScreen(
            driverId: widget.driverId,
            mobile: widget.mobile,
            personalPicturePath: saved.path,
          ),
        ),
      );

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('Personal picture', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
          child: Column(
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 14),
              Center(
                child: ClipOval(
                  child: Image.file(
                    File(widget.imagePath),
                    width: 220,
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Continue if the picture is clear and\nwell-lit',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _lightGreen,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _saving ? null : _usePicture,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: ViteLoader(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.black87)),
                        )
                      : const Text('Use picture', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Retake', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


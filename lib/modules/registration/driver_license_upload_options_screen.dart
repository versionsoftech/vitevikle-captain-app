import 'package:flutter/material.dart';
import 'package:vite_captain/modules/registration/document_camera_screen.dart';

enum DriverLicenseSlot { front, back, selfie }

class DriverLicenseUploadOptionsScreen extends StatelessWidget {
  const DriverLicenseUploadOptionsScreen({
    super.key,
    required this.slot,
  });

  final DriverLicenseSlot slot;

  static const Color _lightGreen = Color(0xFFB7E11A);

  String get _title => 'Driver license';

  String get _headline {
    if (slot == DriverLicenseSlot.back) return 'Take a picture of driver license back side.';
    if (slot == DriverLicenseSlot.selfie) return 'Take a selfie with driver license.';
    return 'Take a picture of driver license front side.';
  }

  String get _illustrationAsset {
    if (slot == DriverLicenseSlot.selfie) return 'assets/images/card2.png';
    return 'assets/images/card.png';
  }

  double get _illustrationHeight {
    if (slot == DriverLicenseSlot.selfie) return 240;
    return 220;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: Center(child: Text('Close', style: TextStyle(fontWeight: FontWeight.w800))),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Text(
                _title,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              _check(context, _headline),
              const SizedBox(height: 10),
              _check(context, "Please don’t use screenshots, copies, or printed photos."),
              const SizedBox(height: 10),
              _check(context, 'No filters, your face and all the details must be clearly visible'),
              const SizedBox(height: 22),
              Expanded(
                child: Center(
                  child: Image.asset(
                    _illustrationAsset,
                    height: _illustrationHeight,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _lightGreen,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    final path = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DocumentCameraScreen(),
                      ),
                    );
                    if (!context.mounted) return;
                    Navigator.pop(context, path);
                  },
                  child: const Text('Take a picture', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _check(BuildContext context, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check, color: Colors.black87, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}


import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/modules/registration/document_camera_screen.dart';
import 'package:vite_captain/providers/document_verification_provider.dart';
import 'package:vite_captain/screens/document_capture_instruction_screen.dart';
import 'package:vite_captain/screens/document_selfie_camera_screen.dart';
import 'package:vite_captain/widgets/curved_green_app_bar.dart';

class LicenseVerificationScreen extends StatefulWidget {
  const LicenseVerificationScreen({super.key});

  @override
  State<LicenseVerificationScreen> createState() => _LicenseVerificationScreenState();
}

class _LicenseVerificationScreenState extends State<LicenseVerificationScreen> {
  static const Color _primary = Color(0xFF369D01);
  static const Color _danger = Color(0xFFE53935);
  static const Color _bg = Color(0xFFF6F7F9);

  late final TextEditingController _numberController;
  late final TextEditingController _expiryController;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    final docs = context.read<DocumentVerificationProvider>();
    _numberController = TextEditingController(text: docs.licenseNumber);
    _expiryController = TextEditingController(text: docs.licenseExpiry);

    _numberController.addListener(() {
      context.read<DocumentVerificationProvider>().updateLicense(number: _numberController.text);
    });

    _expiryController.addListener(() {
      context.read<DocumentVerificationProvider>().updateLicense(expiry: _expiryController.text);
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  InputDecoration _fieldDecoration({required String label, required String hint, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF1F2F4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _primary, width: 1.5),
      ),
      suffixIcon: suffixIcon,
    );
  }

  void _showSnack(String message, {Color backgroundColor = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  Future<void> _capture({required String title, required bool isSelfie}) async {
    final String? captured = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) {
          return DocumentCaptureInstructionScreen(
            title: title,
            subtitleLines: isSelfie
                ? <String>[
                    'Take a selfie holding your License next to your face. Make sure your face and license details are clearly visible.',
                  ]
                : <String>[
                    'Take a clear picture of your License.',
                    'No screenshots or blurred images.',
                  ],
            illustrationAssetPath: isSelfie ? 'assets/images/card2.png' : 'assets/images/card.png',
            illustrationMaxHeight: isSelfie ? 240 : 220,
            cameraScreenBuilder: (_) {
              if (isSelfie) return const DocumentSelfieCameraScreen(title: 'Selfie with License');
              return const DocumentCameraScreen(title: 'Driver License');
            },
          );
        },
      ),
    );

    if (!mounted) return;
    if (captured == null || captured.trim().isEmpty) return;

    final docs = context.read<DocumentVerificationProvider>();

    if (title == 'License Front') {
      await docs.updateLicense(front: captured);
    } else if (title == 'License Back') {
      await docs.updateLicense(back: captured);
    } else {
      await docs.updateLicense(selfie: captured);
    }
  }

  Widget _uploadBox({required String label, required String? path, required VoidCallback onTap}) {
    final hasImage = (path ?? '').trim().isNotEmpty;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 92,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: const [
                  BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: hasImage
                            ? Image.file(
                                File(path!),
                                key: ValueKey<String>(path),
                                fit: BoxFit.cover,
                              )
                            : Center(
                                key: ValueKey<String>('empty'),
                                child: Icon(Icons.add, size: 30, color: Theme.of(context).colorScheme.onSurface),
                              ),
                      ),
                    ),
                    if (hasImage)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
                          child: const Icon(Icons.check, color: Colors.white, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final initial = _expiryDate ?? DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: _primary),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    if (!mounted) return;

    setState(() {
      _expiryDate = DateTime(picked.year, picked.month, picked.day);
      _expiryController.text = _formatDate(_expiryDate!);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: curvedGreenAppBar(
        title: 'Driver License',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<DocumentVerificationProvider>(
          builder: (context, docs, _) {
            final status = docs.licenseStatus;
            final isApproved = status == DocumentStatus.approved;

            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: status == DocumentStatus.approved ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: status == DocumentStatus.approved ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        status == DocumentStatus.approved ? Icons.check_circle : Icons.info,
                        color: status == DocumentStatus.approved ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status == DocumentStatus.approved ? 'Approved' : 'Pending',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _uploadBox(
                      label: 'Front Image',
                      path: docs.licenseFront,
                      onTap: isApproved ? () {} : () => _capture(title: 'License Front', isSelfie: false),
                    ),
                    const SizedBox(width: 12),
                    _uploadBox(
                      label: 'Back Image',
                      path: docs.licenseBack,
                      onTap: isApproved ? () {} : () => _capture(title: 'License Back', isSelfie: false),
                    ),
                    const SizedBox(width: 12),
                    _uploadBox(
                      label: 'Selfie with\nLicense',
                      path: docs.licenseSelfie,
                      onTap: isApproved ? () {} : () => _capture(title: 'License Selfie', isSelfie: true),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _numberController,
                  enabled: !isApproved,
                  keyboardType: TextInputType.text,
                  decoration: _fieldDecoration(
                    label: 'License Number',
                    hint: 'Enter License Number',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _expiryController,
                  readOnly: true,
                  onTap: isApproved ? null : _pickExpiry,
                  decoration: _fieldDecoration(
                    label: 'Expiry Date',
                    hint: 'Select expiry date',
                    suffixIcon: const Icon(Icons.calendar_month, color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 22),
                if (!isApproved)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        if (docs.licenseStatus != DocumentStatus.approved) {
                          _showSnack('Please complete all fields', backgroundColor: _danger);
                          return;
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}


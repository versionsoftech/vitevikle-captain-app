import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/modules/registration/document_camera_screen.dart';
import 'package:vite_captain/providers/document_verification_provider.dart';
import 'package:vite_captain/screens/document_capture_instruction_screen.dart';
import 'package:vite_captain/screens/document_selfie_camera_screen.dart';
import 'package:vite_captain/widgets/curved_green_app_bar.dart';

class AadharVerificationScreen extends StatefulWidget {
  const AadharVerificationScreen({super.key});

  @override
  State<AadharVerificationScreen> createState() => _AadharVerificationScreenState();
}

class _AadharVerificationScreenState extends State<AadharVerificationScreen> {
  static const Color _primary = Color(0xFF369D01);
  static const Color _danger = Color(0xFFE53935);
  static const Color _bg = Color(0xFFF6F7F9);

  late final TextEditingController _numberController;

  @override
  void initState() {
    super.initState();
    final docs = context.read<DocumentVerificationProvider>();
    _numberController = TextEditingController(text: docs.aadharNumber);
    _numberController.addListener(() {
      context.read<DocumentVerificationProvider>().updateAadhar(number: _numberController.text);
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  bool _validAadhar(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^\d{12}$').hasMatch(digits);
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
                    'Take a selfie holding your Aadhar next to your face. Make sure your face and Aadhar details are clearly visible.',
                  ]
                : <String>[
                    'Take a clear picture of your Aadhar card.',
                    'No screenshots or blurred images.',
                  ],
            illustrationAssetPath: isSelfie ? 'assets/images/card2.png' : 'assets/images/card.png',
            illustrationMaxHeight: isSelfie ? 240 : 220,
            cameraScreenBuilder: (_) {
              if (isSelfie) return const DocumentSelfieCameraScreen(title: 'Selfie with Aadhar');
              return const DocumentCameraScreen(title: 'Aadhar');
            },
          );
        },
      ),
    );

    if (!mounted) return;
    if (captured == null || captured.trim().isEmpty) return;

    final docs = context.read<DocumentVerificationProvider>();

    if (title == 'Aadhar Front') {
      await docs.updateAadhar(front: captured);
    } else if (title == 'Aadhar Back') {
      await docs.updateAadhar(back: captured);
    } else {
      await docs.updateAadhar(selfie: captured);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: curvedGreenAppBar(
        title: 'Aadhar Card',
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
            final valid = _validAadhar(_numberController.text);
            final status = docs.aadharStatus;
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
                      label: 'Aadhar Front',
                      path: docs.aadharFront,
                      onTap: isApproved ? () {} : () => _capture(title: 'Aadhar Front', isSelfie: false),
                    ),
                    const SizedBox(width: 12),
                    _uploadBox(
                      label: 'Aadhar Back',
                      path: docs.aadharBack,
                      onTap: isApproved ? () {} : () => _capture(title: 'Aadhar Back', isSelfie: false),
                    ),
                    const SizedBox(width: 12),
                    _uploadBox(
                      label: 'Selfie with\nAadhar',
                      path: docs.aadharSelfie,
                      onTap: isApproved ? () {} : () => _capture(title: 'Aadhar Selfie', isSelfie: true),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _numberController,
                  enabled: !isApproved,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
                  decoration: _fieldDecoration(
                    label: 'Aadhar Card Number',
                    hint: 'Enter Aadhar Number',
                    suffixIcon: _numberController.text.isEmpty
                        ? null
                        : Icon(valid ? Icons.check_circle : Icons.error, color: valid ? _primary : _danger),
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
                        if (docs.aadharStatus != DocumentStatus.approved) {
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


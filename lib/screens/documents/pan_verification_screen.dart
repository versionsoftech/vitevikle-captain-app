import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/modules/registration/document_camera_screen.dart';
import 'package:vite_captain/providers/document_verification_provider.dart';
import 'package:vite_captain/screens/document_capture_instruction_screen.dart';
import 'package:vite_captain/screens/document_selfie_camera_screen.dart';

class PanVerificationScreen extends StatefulWidget {
  const PanVerificationScreen({super.key});

  @override
  State<PanVerificationScreen> createState() => _PanVerificationScreenState();
}

class _PanVerificationScreenState extends State<PanVerificationScreen> {
  static const Color _primary = Color(0xFF369D01);
  static const Color _danger = Color(0xFFE53935);
  static const Color _bg = Color(0xFFF6F7F9);

  late final TextEditingController _numberController;

  @override
  void initState() {
    super.initState();
    final docs = context.read<DocumentVerificationProvider>();
    _numberController = TextEditingController(text: docs.panNumber);
    _numberController.addListener(() {
      context.read<DocumentVerificationProvider>().updatePan(number: _numberController.text);
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  bool _validPan(String value) {
    final v = value.trim().toUpperCase();
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(v);
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
                    'Take a selfie holding your PAN next to your face. Make sure your face and PAN details are clearly visible.',
                  ]
                : <String>[
                    'Take a clear picture of your PAN card.',
                    'No screenshots or blurred images.',
                  ],
            illustrationAssetPath: isSelfie ? 'assets/images/card2.png' : 'assets/images/card.png',
            illustrationMaxHeight: isSelfie ? 240 : 220,
            cameraScreenBuilder: (_) {
              if (isSelfie) return const DocumentSelfieCameraScreen(title: 'Selfie with PAN');
              return const DocumentCameraScreen(title: 'PAN');
            },
          );
        },
      ),
    );

    if (!mounted) return;
    if (captured == null || captured.trim().isEmpty) return;

    final docs = context.read<DocumentVerificationProvider>();

    if (isSelfie) {
      await docs.updatePan(selfie: captured);
    } else {
      await docs.updatePan(image: captured);
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
                color: Colors.white,
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
                            : const Center(
                                key: ValueKey<String>('empty'),
                                child: Icon(Icons.add, size: 30, color: Colors.black87),
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
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('PAN Card', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<DocumentVerificationProvider>(
          builder: (context, docs, _) {
            final valid = _validPan(_numberController.text);
            final status = docs.panStatus;
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
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _uploadBox(
                      label: 'PAN Image',
                      path: docs.panImage,
                      onTap: isApproved ? () {} : () => _capture(title: 'PAN Image', isSelfie: false),
                    ),
                    const SizedBox(width: 12),
                    _uploadBox(
                      label: 'Selfie with\nPAN',
                      path: docs.panSelfie,
                      onTap: isApproved ? () {} : () => _capture(title: 'PAN Selfie', isSelfie: true),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: SizedBox()),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _numberController,
                  enabled: !isApproved,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    LengthLimitingTextInputFormatter(10),
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      return newValue.copyWith(text: newValue.text.toUpperCase(), selection: newValue.selection);
                    }),
                  ],
                  decoration: _fieldDecoration(
                    label: 'PAN Number',
                    hint: 'Enter PAN Number',
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
                        if (docs.panStatus != DocumentStatus.approved) {
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


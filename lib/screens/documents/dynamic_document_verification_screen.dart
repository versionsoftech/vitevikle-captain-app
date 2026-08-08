import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/modules/registration/document_camera_screen.dart';
import 'package:vite_captain/providers/document_verification_provider.dart';
import 'package:vite_captain/screens/document_capture_instruction_screen.dart';
import 'package:vite_captain/screens/document_selfie_camera_screen.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';

class DynamicDocumentVerificationScreen extends StatefulWidget {
  const DynamicDocumentVerificationScreen({
    super.key,
    required this.config,
  });

  final DriverDocumentConfig config;

  @override
  State<DynamicDocumentVerificationScreen> createState() => _DynamicDocumentVerificationScreenState();
}

class _DynamicDocumentVerificationScreenState extends State<DynamicDocumentVerificationScreen> {
  static const Color _primary = Color(0xFF369D01);
  static const Color _danger = Color(0xFFE53935);
  static const Color _bg = Color(0xFFF6F7F9);

  late final TextEditingController _numberController;
  late final TextEditingController _expiryController;
  DateTime? _expiryDate;

  String get _key => (widget.config.key ?? widget.config.id).toLowerCase().trim();

  @override
  void initState() {
    super.initState();
    final docs = context.read<DocumentVerificationProvider>();
    final state = docs.getDynamicState(_key);

    // Debug logs (as requested)
    // ignore: avoid_print
    print('Front: ${widget.config.isFrontImageRequired}');
    // ignore: avoid_print
    print('Back: ${widget.config.isBackImageRequired}');
    // ignore: avoid_print
    print('Selfie: ${widget.config.isSelfieRequired}');
    // ignore: avoid_print
    print('Number: ${widget.config.isDocumentNumberRequired}');

    _numberController = TextEditingController(text: (state['document_number'] ?? '').toString());
    _expiryController = TextEditingController(text: (state['expiry_date'] ?? '').toString());

    _numberController.addListener(() {
      context.read<DocumentVerificationProvider>().updateDynamicState(_key, documentNumber: _numberController.text);
    });

    _expiryController.addListener(() {
      context.read<DocumentVerificationProvider>().updateDynamicState(_key, expiryDate: _expiryController.text);
    });
  }

  Future<void> _submitToBackend(DocumentVerificationProvider docs) async {
    try {
      final driverId = await const SessionService().getDriverId();
      if (driverId == null || driverId.trim().isEmpty) {
        _showSnack('Driver not found. Please login again.', backgroundColor: _danger);
        return;
      }

      final state = docs.getDynamicState(_key);
      final frontPath = (state['front_image'] ?? '').toString().trim();
      final backPath = (state['back_image'] ?? '').toString().trim();
      final selfiePath = (state['selfie_image'] ?? '').toString().trim();
      final docNo = _numberController.text.trim();
      final expiry = _expiryController.text.trim();

      final res = await const ApiService().submitDriverDocument(
        driverId: driverId.trim(),
        documentId: widget.config.id.trim(),
        documentNo: docNo.isEmpty ? null : docNo,
        expiredAt: expiry.isEmpty ? null : expiry,
        frontImagePath: frontPath.isEmpty ? null : frontPath,
        backImagePath: backPath.isEmpty ? null : backPath,
        selfieImagePath: selfiePath.isEmpty ? null : selfiePath,
      );

      if (res['success'] == true) {
        _showSnack('Uploaded Successfully', backgroundColor: _primary);
        if (mounted) Navigator.pop(context);
        return;
      }

      _showSnack((res['message'] ?? 'Upload Failed').toString(), backgroundColor: _danger);
    } catch (_) {
      _showSnack('Upload Failed', backgroundColor: _danger);
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    _expiryController.dispose();
    super.dispose();
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

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _regexValid(String value) {
    final raw = widget.config.validationRegex;
    if (raw == null || raw.trim().isEmpty) return value.trim().isNotEmpty;
    try {
      return RegExp(raw).hasMatch(value.trim());
    } catch (_) {
      return value.trim().isNotEmpty;
    }
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

  Future<void> _capture({required String boxKey, required String title, required bool isSelfie}) async {
    final String? captured = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) {
          return DocumentCaptureInstructionScreen(
            title: title,
            subtitleLines: isSelfie
                ? <String>[
                    'Take a selfie holding your ${widget.config.name} next to your face. Make sure your face and document details are clearly visible.',
                  ]
                : <String>[
                    'Take a clear picture of your ${widget.config.name}.',
                    'No screenshots or blurred images.',
                  ],
            illustrationAssetPath: isSelfie ? 'assets/images/card2.png' : 'assets/images/card.png',
            illustrationMaxHeight: isSelfie ? 240 : 220,
            cameraScreenBuilder: (_) {
              if (isSelfie) return DocumentSelfieCameraScreen(title: title);
              return DocumentCameraScreen(title: widget.config.name);
            },
          );
        },
      ),
    );

    if (!mounted) return;
    if (captured == null || captured.trim().isEmpty) return;

    final docs = context.read<DocumentVerificationProvider>();
    if (boxKey == 'front') {
      await docs.updateDynamicState(_key, frontImagePath: captured);
    } else if (boxKey == 'back') {
      await docs.updateDynamicState(_key, backImagePath: captured);
    } else {
      await docs.updateDynamicState(_key, selfieImagePath: captured);
    }
  }

  Widget _uploadBox({required String label, required String? path, required VoidCallback onTap}) {
    final hasImage = (path ?? '').trim().isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xA6000000),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
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
        title: Text(widget.config.name, style: const TextStyle(fontWeight: FontWeight.w900)),
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
            final state = docs.getDynamicState(_key);
            final status = docs.getServerStatusForConfig(widget.config);
            final isApproved = status == DocumentStatus.approved;

            final String? frontPath = state['front_image'] as String?;
            final String? backPath = state['back_image'] as String?;
            final String? selfiePath = state['selfie_image'] as String?;

            final showFront = widget.config.isFrontImageRequired;
            final showBack = widget.config.isBackImageRequired;
            final showSelfie = widget.config.isSelfieRequired;
            final showNumber = widget.config.isDocumentNumberRequired;
            final showExpiry = widget.config.needExpiredDate;

            final hasAnyField = showFront || showBack || showSelfie || showNumber || showExpiry;
            final canDone = !hasAnyField || docs.isCompleteForConfig(widget.config);

            final List<Widget> boxes = [];
            if (showFront) {
              boxes.add(
                _uploadBox(
                  label: 'Front Image',
                  path: frontPath,
                  onTap: isApproved ? () {} : () => _capture(boxKey: 'front', title: '${widget.config.name} Front', isSelfie: false),
                ),
              );
            }
            if (showBack) {
              boxes.add(
                _uploadBox(
                  label: 'Back Image',
                  path: backPath,
                  onTap: isApproved ? () {} : () => _capture(boxKey: 'back', title: '${widget.config.name} Back', isSelfie: false),
                ),
              );
            }
            if (showSelfie) {
              boxes.add(
                _uploadBox(
                  label: 'Selfie with Document',
                  path: selfiePath,
                  onTap: isApproved ? () {} : () => _capture(boxKey: 'selfie', title: 'Selfie with ${widget.config.name}', isSelfie: true),
                ),
              );
            }

            final numberValid = !showNumber || _regexValid(_numberController.text);

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
                if (!hasAnyField) ...[
                  const SizedBox(height: 28),
                  const Center(
                    child: Text(
                      'No fields required for this document',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
                    ),
                  ),
                ],
                if (boxes.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  GridView.count(
                    crossAxisCount: boxes.length >= 3 ? 3 : boxes.length,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.05,
                    children: boxes,
                  ),
                ],
                if (showNumber) ...[
                  const SizedBox(height: 18),
                  TextField(
                    controller: _numberController,
                    enabled: !isApproved,
                    keyboardType: TextInputType.text,
                    decoration: _fieldDecoration(
                      label: '${widget.config.name} Number',
                      hint: (widget.config.placeholder ?? '').trim().isNotEmpty
                          ? widget.config.placeholder!.trim()
                          : 'Enter ${widget.config.name} Number',
                      suffixIcon: _numberController.text.isEmpty
                          ? null
                          : Icon(numberValid ? Icons.check_circle : Icons.error, color: numberValid ? _primary : _danger),
                    ),
                  ),
                ],
                if (showExpiry) ...[
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
                ],
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
                      onPressed: !canDone
                          ? null
                          : () async {
                              if (!numberValid) {
                                _showSnack('Please enter valid details', backgroundColor: _danger);
                                return;
                              }
                              await _submitToBackend(docs);
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


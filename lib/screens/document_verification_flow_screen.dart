import 'dart:io';
import 'package:vite_captain/widgets/vite_loader.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vite_captain/modules/registration/document_camera_screen.dart';
import 'package:vite_captain/screens/document_capture_instruction_screen.dart';
import 'package:vite_captain/screens/document_selfie_camera_screen.dart';
import 'package:vite_captain/widgets/curved_green_app_bar.dart';

class DocumentVerificationFlowScreen extends StatefulWidget {
  const DocumentVerificationFlowScreen({super.key});

  @override
  State<DocumentVerificationFlowScreen> createState() => _DocumentVerificationFlowScreenState();
}

class _DocumentVerificationFlowScreenState extends State<DocumentVerificationFlowScreen> {
  static const Color _primary = Color(0xFF369D01);
  static const Color _danger = Color(0xFFE53935);
  static const Color _bg = Color(0xFFF6F7F9);

  int _stepIndex = 0;
  bool _submitting = false;

  String? _aadharFront;
  String? _aadharBack;
  String? _aadharSelfie;

  String? _panFront;
  String? _panBack;
  String? _panSelfie;

  String? _dlFront;
  String? _dlBack;
  String? _dlSelfie;

  final TextEditingController _aadharNumberController = TextEditingController();
  final TextEditingController _panNumberController = TextEditingController();
  final TextEditingController _dlNumberController = TextEditingController();
  final TextEditingController _dlExpiryController = TextEditingController();

  DateTime? _dlExpiryDate;

  int get _stepNumber => _stepIndex + 1;

  String get _stepTitle {
    if (_stepIndex == 0) return 'Aadhar Card';
    if (_stepIndex == 1) return 'PAN Card';
    return 'Driving License';
  }

  bool get _stepComplete {
    final imagesOk = () {
      if (_stepIndex == 0) {
        return (_aadharFront ?? '').isNotEmpty && (_aadharBack ?? '').isNotEmpty && (_aadharSelfie ?? '').isNotEmpty;
      }
      if (_stepIndex == 1) {
        return (_panFront ?? '').isNotEmpty && (_panBack ?? '').isNotEmpty && (_panSelfie ?? '').isNotEmpty;
      }
      return (_dlFront ?? '').isNotEmpty && (_dlBack ?? '').isNotEmpty && (_dlSelfie ?? '').isNotEmpty;
    }();

    if (!imagesOk) return false;

    if (_stepIndex == 0) {
      return _isValidAadhar(_aadharNumberController.text);
    }
    if (_stepIndex == 1) {
      return _isValidPan(_panNumberController.text);
    }
    return _dlNumberController.text.trim().isNotEmpty && _dlExpiryDate != null;
  }

  @override
  void initState() {
    super.initState();
    _aadharNumberController.addListener(_onFormChanged);
    _panNumberController.addListener(_onFormChanged);
    _dlNumberController.addListener(_onFormChanged);
  }

  void _onFormChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _aadharNumberController.dispose();
    _panNumberController.dispose();
    _dlNumberController.dispose();
    _dlExpiryController.dispose();
    super.dispose();
  }

  bool _isValidAadhar(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^\d{12}').hasMatch('${digitsOnly}');
  }

  bool _isValidPan(String value) {
    final v = value.trim().toUpperCase();
    return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(v);
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  InputDecoration _fieldDecoration({required String label, required String hint}) {
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
    );
  }

  Widget _stepFields() {
    if (_stepIndex == 0) {
      final valid = _isValidAadhar(_aadharNumberController.text);
      return Column(
        children: [
          TextField(
            controller: _aadharNumberController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
            decoration: _fieldDecoration(
              label: 'Aadhar Card Number',
              hint: 'Enter Aadhar Number',
            ).copyWith(
              suffixIcon: _aadharNumberController.text.isEmpty
                  ? null
                  : Icon(valid ? Icons.check_circle : Icons.error, color: valid ? _primary : _danger),
            ),
          ),
        ],
      );
    }

    if (_stepIndex == 1) {
      final valid = _isValidPan(_panNumberController.text);
      return Column(
        children: [
          TextField(
            controller: _panNumberController,
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
              label: 'PAN Card Number',
              hint: 'Enter PAN Number',
            ).copyWith(
              suffixIcon: _panNumberController.text.isEmpty
                  ? null
                  : Icon(valid ? Icons.check_circle : Icons.error, color: valid ? _primary : _danger),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        TextField(
          controller: _dlNumberController,
          keyboardType: TextInputType.text,
          decoration: _fieldDecoration(
            label: 'Driver License Number',
            hint: 'Enter license number',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _dlExpiryController,
          readOnly: true,
          onTap: () async {
            if (_submitting) return;

            final now = DateTime.now();
            final initial = _dlExpiryDate ?? DateTime(now.year, now.month, now.day);
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
              _dlExpiryDate = DateTime(picked.year, picked.month, picked.day);
              _dlExpiryController.text = _formatDate(_dlExpiryDate!);
            });
          },
          decoration: _fieldDecoration(
            label: 'Expiration Date',
            hint: 'Select expiration date',
          ).copyWith(
            suffixIcon: const Icon(Icons.calendar_month, color: Colors.black54),
          ),
        ),
      ],
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

  Future<void> _captureDocImage({required String docLabel, required bool isSelfie, required void Function(String path) onPicked}) async {
    final String? captured = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) {
          return DocumentCaptureInstructionScreen(
            title: isSelfie ? 'Selfie with $docLabel' : docLabel,
            subtitleLines: isSelfie
                ? <String>[
                    'Take a selfie holding your $docLabel or ID next to your face. Make sure your face and information on your document are clearly visible',
                  ]
                : <String>[
                    'Take a picture of $docLabel front/back side.',
                    "Please don’t use screenshots, copies, or printed photos.",
                    'No filters, your face and all the details must be clearly visible',
                  ],
            illustrationAssetPath: isSelfie ? 'assets/images/card2.png' : 'assets/images/card.png',
            illustrationMaxHeight: isSelfie ? 240 : 220,
            cameraScreenBuilder: (_) {
              if (isSelfie) {
                return DocumentSelfieCameraScreen(title: 'Selfie with $docLabel');
              }
              return DocumentCameraScreen(title: docLabel);
            },
          );
        },
      ),
    );

    if (!mounted) return;
    if (captured == null || captured.trim().isEmpty) return;

    onPicked(captured);
  }

  Future<void> _pickFront() async {
    final doc = _stepTitle;
    await _captureDocImage(
      docLabel: doc,
      isSelfie: false,
      onPicked: (p) {
        setState(() {
          if (_stepIndex == 0) {
            _aadharFront = p;
          } else if (_stepIndex == 1) {
            _panFront = p;
          } else {
            _dlFront = p;
          }
        });
      },
    );
  }

  Future<void> _pickBack() async {
    final doc = _stepTitle;
    await _captureDocImage(
      docLabel: doc,
      isSelfie: false,
      onPicked: (p) {
        setState(() {
          if (_stepIndex == 0) {
            _aadharBack = p;
          } else if (_stepIndex == 1) {
            _panBack = p;
          } else {
            _dlBack = p;
          }
        });
      },
    );
  }

  Future<void> _pickSelfie() async {
    final doc = _stepTitle;
    final selfieLabel = _stepIndex == 0
        ? 'Aadhar'
        : (_stepIndex == 1)
            ? 'PAN'
            : 'Driving License';

    await _captureDocImage(
      docLabel: selfieLabel,
      isSelfie: true,
      onPicked: (p) {
        setState(() {
          if (_stepIndex == 0) {
            _aadharSelfie = p;
          } else if (_stepIndex == 1) {
            _panSelfie = p;
          } else {
            _dlSelfie = p;
          }
        });
      },
    );
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
                          decoration: const BoxDecoration(
                            color: _primary,
                            shape: BoxShape.circle,
                          ),
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

  String? get _frontPath {
    if (_stepIndex == 0) return _aadharFront;
    if (_stepIndex == 1) return _panFront;
    return _dlFront;
  }

  String? get _backPath {
    if (_stepIndex == 0) return _aadharBack;
    if (_stepIndex == 1) return _panBack;
    return _dlBack;
  }

  String? get _selfiePath {
    if (_stepIndex == 0) return _aadharSelfie;
    if (_stepIndex == 1) return _panSelfie;
    return _dlSelfie;
  }

  void _next() {
    if (!_stepComplete) {
      _showSnack('Please upload all images', backgroundColor: _danger);
      return;
    }

    if (_stepIndex < 2) {
      setState(() {
        _stepIndex += 1;
      });
    }
  }

  void _back() {
    if (_stepIndex == 0) return;
    setState(() {
      _stepIndex -= 1;
    });
  }

  Future<void> _confirm() async {
    if (!_stepComplete) {
      _showSnack('Please upload all images', backgroundColor: _danger);
      return;
    }

    final allComplete =
        (_aadharFront ?? '').isNotEmpty && (_aadharBack ?? '').isNotEmpty && (_aadharSelfie ?? '').isNotEmpty &&
        (_panFront ?? '').isNotEmpty && (_panBack ?? '').isNotEmpty && (_panSelfie ?? '').isNotEmpty &&
        (_dlFront ?? '').isNotEmpty && (_dlBack ?? '').isNotEmpty && (_dlSelfie ?? '').isNotEmpty;

    if (!allComplete) {
      _showSnack('Please complete all steps before confirming', backgroundColor: _danger);
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      _showSnack('Documents submitted successfully', backgroundColor: _primary);
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Something went wrong. Please try again.', backgroundColor: _danger);
    } finally {
      if (!mounted) return;
      setState(() {
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canGoNext = _stepComplete && !_submitting;
    final isLast = _stepIndex == 2;

    final frontLabel = _stepIndex == 2 ? 'License front' : '${_stepTitle.split(' ').first} Front';
    final backLabel = _stepIndex == 2 ? 'License back' : '${_stepTitle.split(' ').first} Back';
    final selfieLabel = _stepIndex == 2 ? 'Selfie with license' : 'Selfie with ${_stepTitle.split(' ').first}';

    return Scaffold(
      backgroundColor: _bg,
      appBar: curvedGreenAppBar(
        title: _stepTitle,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _uploadBox(label: frontLabel, path: _frontPath, onTap: _submitting ? () {} : _pickFront),
                  const SizedBox(width: 12),
                  _uploadBox(label: backLabel, path: _backPath, onTap: _submitting ? () {} : _pickBack),
                  const SizedBox(width: 12),
                  _uploadBox(label: selfieLabel, path: _selfiePath, onTap: _submitting ? () {} : _pickSelfie),
                ],
              ),
              const SizedBox(height: 18),
              _stepFields(),
              const Spacer(),
              Row(
                children: [
                  Text(
                    '$_stepNumber of 3',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_stepIndex == 0 || _submitting) ? const Color(0xFFE5E7EB) : const Color(0xFFF1F1F1),
                        foregroundColor: (_stepIndex == 0 || _submitting) ? Colors.black38 : Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: (_stepIndex == 0 || _submitting) ? null : _back,
                      child: const Center(child: Icon(Icons.chevron_left, size: 30)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canGoNext ? _primary : const Color(0xFFE5E7EB),
                          foregroundColor: canGoNext ? Colors.white : Colors.black38,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: !_stepComplete || _submitting ? null : (isLast ? _confirm : _next),
                        child: Center(
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: ViteLoader(strokeWidth: 2.4, color: Colors.white),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      isLast ? 'Confirm' : 'Next',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(width: 10),
                                    Icon(isLast ? Icons.check : Icons.chevron_right, size: 30),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: _stepNumber / 3,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation<Color>(_primary),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}


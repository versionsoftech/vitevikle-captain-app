import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vite_captain/modules/documents/driver_documents_upload_screen.dart';
import 'package:vite_captain/modules/registration/personal_picture_preview_screen.dart';
import 'package:vite_captain/modules/registration/driver_license_upload_options_screen.dart';

class DriverLicenseScreen extends StatefulWidget {
  const DriverLicenseScreen({
    super.key,
    required this.driverId,
    required this.mobile,
    required this.personalPicturePath,
  });

  final String driverId;
  final String mobile;
  final String personalPicturePath;

  @override
  State<DriverLicenseScreen> createState() => _DriverLicenseScreenState();
}

class _DriverLicenseScreenState extends State<DriverLicenseScreen> {
  static const Color _green = Color(0xFF009640);
  static const Color _lightGreen = Color(0xFFB7E11A);

  final TextEditingController _licenseNumberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();

  String? _frontPath;
  String? _backPath;
  String? _selfiePath;

  @override
  void dispose() {
    _licenseNumberController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  Future<void> _pickSlot(DriverLicenseSlot slot) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverLicenseUploadOptionsScreen(slot: slot),
      ),
    );

    if (!mounted) return;
    if (result == null || result.trim().isEmpty) return;

    setState(() {
      if (slot == DriverLicenseSlot.front) {
        _frontPath = result;
      } else if (slot == DriverLicenseSlot.back) {
        _backPath = result;
      } else {
        _selfiePath = result;
      }
    });
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10, 1, 1),
      lastDate: DateTime(now.year + 50, 12, 31),
      initialDate: DateTime(now.year + 1, now.month, now.day),
    );

    if (!mounted) return;
    if (picked == null) return;

    final mm = picked.month.toString().padLeft(2, '0');
    final dd = picked.day.toString().padLeft(2, '0');
    _expiryController.text = '${picked.year}-$mm-$dd';
    setState(() {});
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _next() {
    final licenseNo = _licenseNumberController.text.trim();
    final expiry = _expiryController.text.trim();

    if ((_frontPath ?? '').isEmpty || (_backPath ?? '').isEmpty || (_selfiePath ?? '').isEmpty) {
      _showSnack('Please upload all images');
      return;
    }

    if (licenseNo.isEmpty) {
      _showSnack('Please enter driver license number');
      return;
    }

    if (expiry.isEmpty) {
      _showSnack('Please enter expiration date');
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DriverDocumentsUploadScreen(
          driverId: widget.driverId,
          mobile: widget.mobile,
        ),
      ),
    );
  }

  void _backToPersonalPicture() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalPicturePreviewScreen(
          driverId: widget.driverId,
          mobile: widget.mobile,
          imagePath: widget.personalPicturePath,
        ),
      ),
    );
  }

  Widget _uploadBox({
    required String label,
    required String? path,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Column(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 92,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: (path != null && path.trim().isNotEmpty)
                    ? Image.file(File(path), fit: BoxFit.cover)
                    : Center(
                        child: Icon(Icons.add, size: 32, color: Theme.of(context).colorScheme.onSurface),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String hint,
    required TextEditingController controller,
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      onTap: onTap,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF1F1F1),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text('Driver license', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: Center(
              child: Text('Close', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            children: [
              Row(
                children: [
                  _uploadBox(
                    label: 'Driver license',
                    path: _frontPath,
                    onTap: () => _pickSlot(DriverLicenseSlot.front),
                  ),
                  const SizedBox(width: 12),
                  _uploadBox(
                    label: 'Driver license\nback side',
                    path: _backPath,
                    onTap: () => _pickSlot(DriverLicenseSlot.back),
                  ),
                  const SizedBox(width: 12),
                  _uploadBox(
                    label: 'Selfie with driver\nlicense',
                    path: _selfiePath,
                    onTap: () => _pickSlot(DriverLicenseSlot.selfie),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _field(hint: 'Driver license number', controller: _licenseNumberController),
              const SizedBox(height: 14),
              _field(
                hint: 'Expiration date',
                controller: _expiryController,
                readOnly: true,
                onTap: _pickExpiryDate,
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    '2 of 4',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: _backToPersonalPicture,
                      child: const Icon(Icons.chevron_left, size: 28),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _lightGreen,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: _next,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            SizedBox(width: 10),
                            Icon(Icons.chevron_right, size: 28),
                          ],
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
                  value: 0.5,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation<Color>(_green),
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


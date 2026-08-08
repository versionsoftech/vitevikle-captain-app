import 'package:flutter/material.dart';
import 'package:vite_captain/modules/status/driver_under_review_screen.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';

class DriverDocumentsUploadScreen extends StatefulWidget {
  const DriverDocumentsUploadScreen({
    super.key,
    required this.driverId,
    required this.mobile,
  });

  final String driverId;
  final String mobile;

  @override
  State<DriverDocumentsUploadScreen> createState() => _DriverDocumentsUploadScreenState();
}

class _DriverDocumentsUploadScreenState extends State<DriverDocumentsUploadScreen> {
  final _licenseController = TextEditingController();
  final _rcController = TextEditingController();
  final _insuranceController = TextEditingController();
  final _profileController = TextEditingController();

  bool _loading = false;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final license = _licenseController.text.trim();
    final rc = _rcController.text.trim();
    final insurance = _insuranceController.text.trim();
    final profile = _profileController.text.trim();

    if (license.isEmpty || rc.isEmpty || insurance.isEmpty || profile.isEmpty) {
      _showSnack('Please fill all documents');
      return;
    }

    setState(() => _loading = true);
    final resp = await const ApiService().uploadDriverDocuments(
      driverId: widget.driverId,
      license: license,
      rc: rc,
      insurance: insurance,
      profilePhoto: profile,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (resp['success'] != true) {
      _showSnack((resp['message'] ?? 'Upload failed').toString());
      return;
    }

    await const SessionService().saveDriverId(widget.driverId);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverUnderReviewScreen()),
    );
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _rcController.dispose();
    _insuranceController.dispose();
    _profileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Documents'),
        backgroundColor: const Color(0xFF369D01),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _licenseController,
                decoration: const InputDecoration(labelText: 'License (URL / filename)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rcController,
                decoration: const InputDecoration(labelText: 'RC (URL / filename)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _insuranceController,
                decoration: const InputDecoration(labelText: 'Insurance (URL / filename)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _profileController,
                decoration: const InputDecoration(labelText: 'Profile Photo (URL / filename)'),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF369D01),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                        )
                      : const Text('Submit', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


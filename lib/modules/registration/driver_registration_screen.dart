import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/local_storage_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/screens/home_screen.dart';
import 'package:vite_captain/screens/first_launch_flow_screen.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({
    super.key,
    required this.mobile,
  });

  final String mobile;

  @override
  State<DriverRegistrationScreen> createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _nameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  String _service = 'bike';
  final _categoryController = TextEditingController();

  final _homeWardController = TextEditingController();
  final _roadNearByController = TextEditingController();
  final _cityVillageController = TextEditingController();
  final _tehsilController = TextEditingController();
  final _districtController = TextEditingController();
  final _pinCodeController = TextEditingController();

  bool _loading = false;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _mobileController.text = widget.mobile;
    if (_categoryController.text.trim().isEmpty) {
      _categoryController.text = 'bike';
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF1F1F1),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final category = _categoryController.text.trim();

    final fatherName = _fatherNameController.text.trim();
    final homeWard = _homeWardController.text.trim();
    final roadNearBy = _roadNearByController.text.trim();
    final cityVillage = _cityVillageController.text.trim();
    final tehsil = _tehsilController.text.trim();
    final district = _districtController.text.trim();
    final pinCode = _pinCodeController.text.trim();

    if (name.isEmpty) {
      _showSnack('Please enter name');
      return;
    }

    if (fatherName.isEmpty) {
      _showSnack('Please enter father name');
      return;
    }

    if (email.isEmpty) {
      _showSnack('Please enter email');
      return;
    }

    if (homeWard.isEmpty) {
      _showSnack('Please enter home / ward');
      return;
    }
    if (roadNearBy.isEmpty) {
      _showSnack('Please enter road / near by');
      return;
    }
    if (cityVillage.isEmpty) {
      _showSnack('Please enter city / village');
      return;
    }
    if (tehsil.isEmpty) {
      _showSnack('Please enter tehsil');
      return;
    }
    if (district.isEmpty) {
      _showSnack('Please enter district');
      return;
    }
    if (pinCode.isEmpty) {
      _showSnack('Please enter pin code');
      return;
    }

    if (category.isEmpty) {
      _showSnack('Please enter category');
      return;
    }

    setState(() => _loading = true);
    final resp = await const ApiService().driverRegister(
      fullName: name,
      mobile: widget.mobile,
      email: email,
      service: _service,
      serviceCategories: category,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (resp['success'] != true) {
      _showSnack((resp['message'] ?? 'Registration failed').toString());
      return;
    }

    final driverId = resp['driverId'];
    if (driverId is String && driverId.isNotEmpty) {
      await const SessionService().saveDriverId(driverId);
    }

    final token = resp['token'];
    await const LocalStorageService().saveLogin(
      isLoggedIn: true,
      driverId: driverId?.toString(),
      token: token is String && token.trim().isNotEmpty ? token.trim() : null,
      mobile: widget.mobile,
    );

    await const LocalStorageService().saveDriverSessionFlags(
      status: true,
      isVerified: true,
    );

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const FirstLaunchFlowScreen(next: HomeScreen())),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fatherNameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _categoryController.dispose();
    _homeWardController.dispose();
    _roadNearByController.dispose();
    _cityVillageController.dispose();
    _tehsilController.dispose();
    _districtController.dispose();
    _pinCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Registration'),
        backgroundColor: const Color(0xFF009640),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Text(
                'Create Your Account',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Complete your profile to start driving.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 18),

              _field(label: 'Full Name', controller: _nameController),
              _field(label: 'Father Name', controller: _fatherNameController),
              _field(
                label: 'Mobile Number',
                controller: _mobileController,
                keyboardType: TextInputType.phone,
                readOnly: true,
              ),
              _field(label: 'Email', controller: _emailController, keyboardType: TextInputType.emailAddress),

              _sectionTitle('Address Details'),
              _field(label: 'Home / Ward', controller: _homeWardController),
              _field(label: 'Road / Near By', controller: _roadNearByController),
              _field(label: 'City / Village', controller: _cityVillageController),
              _field(label: 'Tehsil', controller: _tehsilController),
              _field(label: 'District', controller: _districtController),
              _field(label: 'Pin Code', controller: _pinCodeController, keyboardType: TextInputType.number),

              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF009640),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: ViteLoader(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Submit', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


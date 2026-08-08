import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/controllers/profile_controller.dart';
import 'package:vite_captain/screens/personal_picture/personal_picture_instruction_screen.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  DateTime? _dob;
  String _gender = '';
  String _ecName = '';
  String _ecPhone = '';
  String _ecRelation = '';
  late Future<Map<String, String>> _userBasicsFuture;
  bool _isSavingDob = false;
  bool _accountReviewRequired = false;

  @override
  void initState() {
    super.initState();
    _userBasicsFuture = const SessionService().getUserBasics(forceRefresh: true);
    // Hydrate DOB and Emergency Contact from backend so the fields pre-fill correctly on first load
    Future.microtask(() async {
      await _hydrateDob();
      await _hydrateEmergencyContact();
      await _checkAccountReviewStatus();
    });
  }

  Future<void> _checkAccountReviewStatus() async {
    try {
      final token = (await const SessionService().getToken() ?? '').trim();
      if (token.isEmpty) return;
      final res = await const ApiService().getDriverProfile(token: token);
      final ok = res['success'] == true;
      final data = ok ? (res['data'] as Map?) : null;
      final accountReviewRequired = data is Map ? data['account_review_required'] : false;
      if (mounted) {
        setState(() {
          _accountReviewRequired = accountReviewRequired == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _hydrateEmergencyContact() async {
    try {
      final token = (await const SessionService().getToken() ?? '').trim();
      if (token.isEmpty) return;
      final res = await const ApiService().getDriverProfile(token: token);
      final ok = res['success'] == true;
      final data = ok ? (res['data'] as Map?) : null;
      final ec = data is Map ? data['emergency_contact'] : null;
      if (ec is Map && mounted) {
        setState(() {
          _ecName = (ec['name'] ?? '').toString().trim();
          _ecPhone = (ec['phone'] ?? '').toString().trim();
          _ecRelation = (ec['relationship'] ?? '').toString().trim();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveEmergencyContact({required String name, required String phone, String? relation}) async {
    debugPrint('EMERGENCY_SAVE_CLICKED');
    final token = (await const SessionService().getToken() ?? '').trim();
    if (token.isEmpty) {
      debugPrint('EMERGENCY_SAVE_ERROR auth=missing_token');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authentication failed')));
      return;
    }
    final redacted = token.length > 12 ? (token.substring(0, 6) + '...' + token.substring(token.length - 6)) : token;
    debugPrint('EMERGENCY_AUTH token=' + (redacted.isEmpty ? '(missing)' : redacted));
    debugPrint('EMERGENCY_AUTH header=' + (token.isNotEmpty ? 'Bearer <present>' : '(none)'));
    debugPrint('EMERGENCY_VALIDATION_PASSED');
    debugPrint('EMERGENCY_PAYLOAD');
    debugPrint({
          'name': name,
          'phone': phone,
          'relationship': relation ?? ''
        }.toString());
    debugPrint('EMERGENCY_API_REQUEST payload=' + {
          'name': name,
          'phone': phone,
          'relationship': relation ?? ''
        }.toString());
    try {
      final res = await const ApiService().updateEmergencyContact(
        token: token,
        name: name,
        phone: phone,
        relationship: relation,
      );
      debugPrint('EMERGENCY_API_RESPONSE body=' + res.toString());
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          _ecName = name.trim();
          _ecPhone = phone.trim();
          _ecRelation = (relation ?? '').trim();
        });
        debugPrint('EMERGENCY_SAVE_SUCCESS');
        final msg = (res['message'] ?? 'Emergency contact saved').toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } else {
        final msg = (res['message'] ?? 'Failed to save emergency contact').toString();
        debugPrint('EMERGENCY_SAVE_ERROR message=' + msg);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e, st) {
      debugPrint('EMERGENCY_SAVE_ERROR exception=' + e.toString());
      debugPrint(st.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unexpected Error')));
    }
  }

  Future<void> _saveGender(String value) async {
    try {
      final token = (await const SessionService().getToken() ?? '').trim();
      if (token.isEmpty) return;
      final res = await const ApiService().updateDriverProfile(
        token: token,
        gender: value.toLowerCase(),
      );
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'];
        if (data is Map<String, dynamic>) {
          await const SessionService().updateCachedUserBasics(data);
        } else if (data is Map) {
          await const SessionService().updateCachedUserBasics(Map<String, dynamic>.from(data));
        }
        setState(() => _gender = value.toLowerCase());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gender updated')));
        await _refreshUserBasics();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update gender')));
      }
    } catch (_) {}
  }

  Future<void> _openEditGenderSheet() async {
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final current = _gender;
        Widget tile(String label, String value) {
          final active = current == value;
          return ListTile(
            leading: Icon(active ? Icons.radio_button_checked : Icons.radio_button_off,
                color: active ? Colors.green : Colors.grey),
            title: Text(label),
            onTap: () => Navigator.pop(context, value),
          );
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(height: 4, width: 36, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 12),
              const Text('Select Gender', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              tile('Male', 'male'),
              tile('Female', 'female'),
              tile('Other', 'other'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null && selected.trim().isNotEmpty) {
      await _saveGender(selected.trim());
    }
  }

  Future<void> _refreshUserBasics() async {
    setState(() {
      _userBasicsFuture = const SessionService().getUserBasics(forceRefresh: true);
    });
    await _userBasicsFuture;
  }

  void _openEditNameSheet(BuildContext context, String initialName) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return EditNameBottomSheet(initialName: initialName);
      },
    );
    if (!mounted) return;
    if (changed == true) {
      await _refreshUserBasics();
    }
  }

  void _openEditEmailSheet(BuildContext context, String currentEmail) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return EditEmailBottomSheet(initialEmail: currentEmail);
      },
    );
    if (!mounted) return;
    if (changed == true) {
      await _refreshUserBasics();
    }
  }

  Future<void> _hydrateDob() async {
    try {
      final token = (await const SessionService().getToken() ?? '').trim();
      if (token.isEmpty) return;
      final res = await const ApiService().getDriverProfile(token: token);
      final data = res['success'] == true ? res['data'] : null;
      if (data is Map) {
        final dobRaw = data['dateOfBirth'];
        if (dobRaw != null && dobRaw.toString().trim().isNotEmpty && dobRaw.toString() != 'null') {
          final parsed = DateTime.tryParse(dobRaw.toString());
          if (parsed != null && mounted) setState(() => _dob = parsed);
        }
        final gRaw = (data['gender'] ?? '').toString().trim().toLowerCase();
        if (mounted) setState(() => _gender = gRaw);
      }
    } catch (_) {}
  }

  Future<void> _pickDob() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      setState(() {
        _dob = pickedDate;
      });
      await _saveDob();
    }
  }

  Future<void> _saveDob() async {
    if (_dob == null) return;
    if (_isSavingDob) return;
    setState(() => _isSavingDob = true);
    try {
      final token = (await const SessionService().getToken() ?? '').trim();
      if (token.isEmpty) return;
      final dobIso = _dob!.toIso8601String();
      final res = await const ApiService().updateDriverProfile(
        token: token,
        dateOfBirth: dobIso,
      );
      if (res['success'] == true) {
        final data = res['data'];
        if (data is Map<String, dynamic>) {
          await const SessionService().updateCachedUserBasics(data);
        } else if (data is Map) {
          await const SessionService().updateCachedUserBasics(Map<String, dynamic>.from(data));
        } else {
          await const SessionService().updateCachedUserBasics({'dateOfBirth': dobIso});
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Date of birth updated')));
        await _refreshUserBasics();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update DOB')));
      }
    } finally {
      if (mounted) setState(() => _isSavingDob = false);
    }
  }

  Widget _profileRow({
    required IconData icon,
    required String title,
    required String value,
    bool highlightValue = false,
    bool showChevron = true,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: Colors.grey[700]),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: highlightValue ? Colors.orange : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
                if (trailing == null && showChevron)
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: Colors.grey.shade300,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dobText = _dob == null
        ? 'Required'
        : DateFormat('MMMM d, yyyy').format(_dob!);

    final emergencyText = (_ecName.isEmpty || _ecPhone.isEmpty)
        ? 'Required'
        : '${_ecName} ${_ecPhone}${_ecRelation.isNotEmpty ? ' • ' + _ecRelation : ''}';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text('Help'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FutureBuilder<Map<String, String>>(
            future: _userBasicsFuture,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const <String, String>{};
              final name = (data['name'] ?? '').trim();
              final mobile = (data['mobile'] ?? '').trim();
              final email = (data['email'] ?? '').trim();
              final imageUrl = (data['imageUrl'] ?? '').trim();

              return RefreshIndicator(
                onRefresh: _refreshUserBasics,
                child: ListView(
                  children: [
                    const SizedBox(height: 16),
                    // Account Review Warning Banner
                    if (_accountReviewRequired)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Your account is under review due to repeated ride expiries.',
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Center(
                      child: ValueListenableBuilder<String?>(
                        valueListenable: ProfileController.profileImagePath,
                        builder: (context, _, __) {
                          final pickedProvider = ProfileController.imageProviderOrNull();

                          return GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PersonalPictureInstructionScreen(),
                                ),
                              );
                              if (!mounted) return;
                              await _refreshUserBasics();
                            },
                            child: pickedProvider != null
                                ? CircleAvatar(
                                    radius: 43,
                                    backgroundColor: Colors.grey.shade200,
                                    backgroundImage: pickedProvider,
                                  )
                                : (imageUrl.isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          imageUrl,
                                          key: ValueKey(imageUrl),
                                          width: 86,
                                          height: 86,
                                          fit: BoxFit.cover,
                                          headers: const {'Cache-Control': 'no-cache'},
                                          errorBuilder: (context, error, stackTrace) {
                                            return CircleAvatar(
                                              radius: 43,
                                              backgroundColor: Colors.grey.shade200,
                                              child: const Icon(
                                                Icons.person,
                                                color: Colors.grey,
                                                size: 40,
                                              ),
                                            );
                                          },
                                        ),
                                      )
                                    : CircleAvatar(
                                        radius: 43,
                                        backgroundColor: Colors.grey.shade200,
                                        child: const Icon(
                                          Icons.person,
                                          color: Colors.grey,
                                          size: 40,
                                        ),
                                      )),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _profileRow(
                      icon: Icons.person_outline,
                      title: 'Name',
                      value: name.isNotEmpty ? name : '-',
                      onTap: () => _openEditNameSheet(context, name),
                    ),
                    _profileRow(
                      icon: Icons.phone_outlined,
                      title: 'Phone Number',
                      value: mobile.isNotEmpty ? mobile : '-',
                      showChevron: false,
                    ),
                    _profileRow(
                      icon: Icons.email_outlined,
                      title: 'Email',
                      value: email.isNotEmpty ? email : 'Required',
                      highlightValue: email.isEmpty,
                      onTap: () => _openEditEmailSheet(context, email),
                    ),
                    _profileRow(
                      icon: Icons.person_pin_outlined,
                      title: 'Gender',
                      value: _gender.isEmpty ? '-' : (_gender[0].toUpperCase() + _gender.substring(1)),
                      onTap: _openEditGenderSheet,
                    ),
                    _profileRow(
                      icon: Icons.calendar_today_outlined,
                      title: 'Date of Birth',
                      value: dobText,
                      highlightValue: _dob == null,
                      onTap: _pickDob,
                    ),
                    _profileRow(
                      icon: Icons.badge_outlined,
                      title: 'Member Since',
                      value: 'March 2026',
                      showChevron: false,
                    ),
                    _profileRow(
                      icon: Icons.health_and_safety_outlined,
                      title: 'Emergency Contact',
                      value: emergencyText,
                      highlightValue: _ecName.isEmpty || _ecPhone.isEmpty,
                      onTap: () => _openEmergencyEditSheet(context),
                      trailing: TextButton(
                        onPressed: () => _openEmergencyEditSheet(context),
                        child: Text(
                          (_ecName.isEmpty || _ecPhone.isEmpty) ? 'Add' : 'Edit',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

extension on _ProfileScreenState {
  Future<void> _openEmergencyEditSheet(BuildContext context) async {
    final changed = await showModalBottomSheet<_EmergencyPayload>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return EmergencyContactBottomSheet(
          initialName: _ecName,
          initialPhone: _ecPhone,
          initialRelation: _ecRelation,
        );
      },
    );
    if (!mounted) return;
    if (changed == null) return;
    await _saveEmergencyContact(name: changed.name, phone: changed.phone, relation: changed.relation);
  }
}

class _EmergencyPayload {
  final String name;
  final String phone;
  final String relation;
  const _EmergencyPayload({required this.name, required this.phone, required this.relation});
}

class EmergencyContactBottomSheet extends StatefulWidget {
  final String initialName;
  final String initialPhone;
  final String initialRelation;

  const EmergencyContactBottomSheet({super.key, required this.initialName, required this.initialPhone, required this.initialRelation});

  @override
  State<EmergencyContactBottomSheet> createState() => _EmergencyContactBottomSheetState();
}

class _EmergencyContactBottomSheetState extends State<EmergencyContactBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  String _relation = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
    _relation = widget.initialRelation;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  InputDecoration _decoration({required String hintText, IconData? icon}) {
    return InputDecoration(
      prefixIcon: icon != null ? Icon(icon) : null,
      hintText: hintText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Emergency Contact',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: _decoration(hintText: 'Full Name', icon: Icons.person_outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: _decoration(hintText: '+91XXXXXXXXXX', icon: Icons.phone_outlined),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _relation.isEmpty ? null : _relation,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'Father', child: Text('Father')),
                  DropdownMenuItem(value: 'Mother', child: Text('Mother')),
                  DropdownMenuItem(value: 'Brother', child: Text('Brother')),
                  DropdownMenuItem(value: 'Sister', child: Text('Sister')),
                  DropdownMenuItem(value: 'Wife', child: Text('Wife')),
                  DropdownMenuItem(value: 'Husband', child: Text('Husband')),
                  DropdownMenuItem(value: 'Friend', child: Text('Friend')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _relation = (v ?? '').trim()),
                decoration: _decoration(hintText: 'Relationship', icon: Icons.group_outlined),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  backgroundColor: Colors.green,
                ),
                onPressed: _isSaving ? null : () async {
                  debugPrint('EMERGENCY_SAVE_BUTTON_CLICKED');
                  final name = _nameController.text.trim();
                  final phone = _phoneController.text.trim();
                  debugPrint('EMERGENCY_PAYLOAD');
                  debugPrint({'name': name, 'phone': phone, 'relationship': _relation}.toString());
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
                    return;
                  }
                  if (phone.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mobile number is required')));
                    return;
                  }
                  final re = RegExp(r'^[+]?\d{8,15}?');
                  if (!re.hasMatch(phone)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid mobile number')));
                    return;
                  }
                  setState(() => _isSaving = true);
                  try {
                    if (!mounted) return;
                    Navigator.pop(context, _EmergencyPayload(name: name, phone: phone, relation: _relation));
                  } finally {
                    if (mounted) setState(() => _isSaving = false);
                  }
                },
                child: const Text(
                  'Save Changes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditNameBottomSheet extends StatefulWidget {
  final String initialName;

  const EditNameBottomSheet({super.key, required this.initialName});

  @override
  State<EditNameBottomSheet> createState() => _EditNameBottomSheetState();
}

class _EditNameBottomSheetState extends State<EditNameBottomSheet> {
  late final TextEditingController _nameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  InputDecoration _decoration({required String hintText}) {
    return InputDecoration(
      prefixIcon: const Icon(Icons.person_outline),
      hintText: hintText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Name',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: _decoration(hintText: 'Full Name'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
              ),
              onPressed: _isSaving ? null : () async {
                debugPrint('LOG 1: Save button clicked');
                final newName = _nameController.text.trim();
                if (newName.isEmpty) {
                  debugPrint('LOG 2: Form validation failed - name empty');
                  Navigator.pop(context);
                  return;
                }
                debugPrint('LOG 2: Form validation passed');
                try {
                  setState(() => _isSaving = true);
                  debugPrint('LOG 3: Preparing payload');
                  // IMPORTANT: update-profile (controller/user.controller.js) uses 'user' collection (_id).
                  // Prefer id from basics (JWT/CheckUserDetails), fallback to driver_id.
                  final token = (await const SessionService().getToken() ?? '').trim();
                  if (token.isEmpty) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authentication failed')));
                    return;
                  }
                  final res = await const ApiService().updateDriverProfile(
                    token: token,
                    fullName: newName,
                  );
                  if (res['success'] != true) {
                    if (!mounted) return;
                    final msg = (res['message'] ?? 'Update failed').toString();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                    return;
                  }
                  final data = res['data'];
                  if (data is Map<String, dynamic>) {
                    await const SessionService().updateCachedUserBasics(data);
                  } else if (data is Map) {
                    await const SessionService().updateCachedUserBasics(Map<String, dynamic>.from(data));
                  } else {
                    await const SessionService().updateCachedUserBasics({'fullName': newName});
                  }
                  if (!mounted) return;
                  debugPrint('LOG 11: Updating local storage (will trigger parent refresh via return value)');
                  Navigator.pop(context, true);
                  debugPrint('LOG 12: Refreshing UI (popped bottom sheet with success=true)');
                } catch (_) {
                  debugPrint('LOG ERROR: Exception during save');
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update failed')));
                } finally {
                  if (mounted) setState(() => _isSaving = false);
                }
              },
              child: const Text(
                'Save Changes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditEmailBottomSheet extends StatefulWidget {
  final String initialEmail;
  const EditEmailBottomSheet({super.key, required this.initialEmail});

  @override
  State<EditEmailBottomSheet> createState() => _EditEmailBottomSheetState();
}

class _EditEmailBottomSheetState extends State<EditEmailBottomSheet> {
  late final TextEditingController _emailController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Email',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.mail_outline),
                hintText: 'John@abc.com',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 55),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: _isSaving ? null : () async {
                final newEmail = _emailController.text.trim();
                if (newEmail.isEmpty) {
                  Navigator.pop(context);
                  return;
                }
                try {
                  setState(() => _isSaving = true);
                  final token = (await const SessionService().getToken() ?? '').trim();
                  if (token.isEmpty) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authentication failed')));
                    return;
                  }
                  final res = await const ApiService().updateDriverProfile(
                    token: token,
                    email: newEmail,
                  );
                  if (res['success'] != true) {
                    if (!mounted) return;
                    final msg = (res['message'] ?? 'Update failed').toString();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                    return;
                  }
                  final data = res['data'];
                  if (data is Map<String, dynamic>) {
                    await const SessionService().updateCachedUserBasics(data);
                  } else if (data is Map) {
                    await const SessionService().updateCachedUserBasics(Map<String, dynamic>.from(data));
                  } else {
                    await const SessionService().updateCachedUserBasics({'email': newEmail});
                  }
                  if (!mounted) return;
                  Navigator.pop(context, true);
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update failed')));
                } finally {
                  if (mounted) setState(() => _isSaving = false);
                }
              },
              child: const Text(
                'Save Changes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


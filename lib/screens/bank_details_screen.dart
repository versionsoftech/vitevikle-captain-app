import 'dart:convert';
import 'package:vite_captain/widgets/vite_loader.dart';

import 'package:flutter/material.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:dio/dio.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/widgets/curved_green_app_bar.dart';

class BankDetailsScreen extends StatefulWidget {
  final bool startEditing;

  const BankDetailsScreen({super.key, this.startEditing = false});

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  static const Color _primary = Color(0xFF369D01);
  static const Color _danger = Color(0xFFE53935);
  static const Color _bg = Color(0xFFF6F7F9);

  static const List<DropdownMenuItem<String>> _payoutItems = <DropdownMenuItem<String>>[
    DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
    DropdownMenuItem(value: 'razorpay', child: Text('Razorpay')),
    DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
  ];

  final SessionService _sessionService = const SessionService();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _accountController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _holderController;
  late final TextEditingController _ifscController;
  late final TextEditingController _emailController;

  String _payoutMethod = 'bank_transfer';
  String _bankStatus = 'not_submitted';
  bool _isReadOnly = false;
  bool _hydrating = true;
  bool _submitting = false;

  Map<String, dynamic>? _bankData;

  @override
  void initState() {
    super.initState();
    _accountController = TextEditingController();
    _bankNameController = TextEditingController();
    _holderController = TextEditingController();
    _ifscController = TextEditingController();
    _emailController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _accountController.dispose();
    _bankNameController.dispose();
    _holderController.dispose();
    _ifscController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _hydrating = true;
    });

    try {
      final token = await _sessionService.getToken();
      final driverId = await _sessionService.getDriverId();
      final t = (token ?? '').trim();
      final d = (driverId ?? '').trim();

      if (t.isEmpty || d.isEmpty) {
        if (!mounted) return;
        setState(() {
          _bankData = null;
          _bankStatus = 'not_submitted';
          _isReadOnly = false;
        });
        return;
      }

      final uri = Uri.parse('$baseUrl/driver/bank-details/$d');
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer $t',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      Map<String, dynamic>? decoded;
      try {
        dynamic raw = res.data;
        if (raw is String) raw = jsonDecode(raw);
        if (raw is Map<String, dynamic>) decoded = raw;
      } catch (_) {
        decoded = null;
      }

      final data = decoded is Map<String, dynamic> ? decoded!['data'] : null;
      final exists = data != null && data is Map;
      final bankMap = exists ? Map<String, dynamic>.from(data as Map) : null;

      if (!mounted) return;
      setState(() {
        _bankData = bankMap;

        if (exists && bankMap != null) {
          _holderController.text = (bankMap['holder_name'] ?? '').toString();
          _bankNameController.text = (bankMap['bank_name'] ?? '').toString();
          _accountController.text = (bankMap['account_no'] ?? '').toString();
          _ifscController.text = (bankMap['ifsc_code'] ?? '').toString();
          _emailController.text = (bankMap['email'] ?? '').toString();
          _payoutMethod = (bankMap['payout_method'] ?? 'bank_transfer').toString().trim();
          _bankStatus = (bankMap['status'] ?? 'pending').toString().trim();
          _isReadOnly = !widget.startEditing;
        } else {
          _bankStatus = 'not_submitted';
          _isReadOnly = false;
        }
      });
    } catch (e) {
      _showSnack(e.toString(), backgroundColor: _danger);
    } finally {
      if (mounted) {
        setState(() {
          _hydrating = false;
        });
      }
    }
  }

  InputDecoration _fieldDecoration({required String label, String? hint}) {
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

  Color _statusColor(String s) {
    switch (s.trim().toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _statusBanner() {
    if (_bankStatus == 'not_submitted') return const SizedBox.shrink();

    final colors = _bankStatus == 'approved'
        ? const [Color(0xFFd4edda), Color(0xFFc3e6cb)]
        : _bankStatus == 'rejected'
            ? const [Color(0xFFf8d7da), Color(0xFFf5c6cb)]
            : const [Color(0xFFfff3cd), Color(0xFFffeeba)];

    final icon = _bankStatus == 'approved'
        ? Icons.verified
        : _bankStatus == 'rejected'
            ? Icons.cancel
            : Icons.hourglass_bottom;

    final text = _bankStatus == 'approved'
        ? 'Bank Approved'
        : _bankStatus == 'rejected'
            ? 'Bank Rejected'
            : 'Under Review';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: _statusColor(_bankStatus)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {Color backgroundColor = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  bool _validEmail(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
  }

  Future<void> _submit() async {
    if (_isReadOnly) return;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final updating = _bankData != null;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(updating ? 'Update bank' : 'Confirm'),
          content: Text(updating ? 'Save these bank details?' : 'Submit bank details?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
          ],
        );
      },
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() {
      _submitting = true;
    });

    try {
      final token = await _sessionService.getToken();
      final driverId = await _sessionService.getDriverId();
      final t = (token ?? '').trim();
      final d = (driverId ?? '').trim();

      if (t.isEmpty || d.isEmpty) {
        _showSnack('Unauthorized', backgroundColor: _danger);
        return;
      }

      final uri = Uri.parse('$baseUrl/driver/bank-details');
      final res = await DioClient.dio.post(
        uri.toString(),
        data: {
          'driver_id': d,
          'holder_name': _holderController.text.trim(),
          'bank_name': _bankNameController.text.trim(),
          'account_no': _accountController.text.trim(),
          'ifsc_code': _ifscController.text.trim().toUpperCase(),
          'email': _emailController.text.trim(),
          'payout_method': _payoutMethod.trim(),
        },
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer $t',
            'Content-Type': 'application/json',
          },
        ),
      );

      Map<String, dynamic>? decoded;
      try {
        dynamic raw = res.data;
        if (raw is String) raw = jsonDecode(raw);
        if (raw is Map<String, dynamic>) decoded = raw;
      } catch (_) {
        decoded = null;
      }

      final success = decoded?['success'] == true;
      if (!success) {
        _showSnack((decoded?['message'] ?? 'Submit failed').toString(), backgroundColor: _danger);
        return;
      }

      _showSnack(updating ? 'Bank details updated' : 'Bank details submitted successfully');
      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: curvedGreenAppBar(
        title: 'Bank Details',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: SafeArea(
        child: _hydrating
            ? const Center(child: ViteLoader(color: _primary))
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  children: [
                    _statusBanner(),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _holderController,
                      enabled: !_isReadOnly,
                      decoration: _fieldDecoration(label: 'Account Holder Name'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Account holder name is required' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _bankNameController,
                      enabled: !_isReadOnly,
                      decoration: _fieldDecoration(label: 'Bank Name'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Bank name is required' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _accountController,
                      enabled: !_isReadOnly,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDecoration(label: 'Account Number'),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'Account number is required';
                        if (!RegExp(r'^\d+$').hasMatch(value)) return 'Account number must be numeric';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _ifscController,
                      enabled: !_isReadOnly,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _fieldDecoration(label: 'IFSC Code'),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'IFSC code is required';
                        final normalized = value.toUpperCase();
                        if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(normalized)) {
                          return 'Enter valid IFSC code';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _emailController,
                      enabled: !_isReadOnly,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _fieldDecoration(label: 'Email'),
                      validator: (v) {
                        final value = (v ?? '').trim();
                        if (value.isEmpty) return 'Email is required';
                        if (!_validEmail(value)) return 'Enter valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _payoutMethod,
                      items: _payoutItems,
                      onChanged: _isReadOnly
                          ? null
                          : (val) async {
                              final v = (val ?? 'bank_transfer').trim();
                              setState(() {
                                _payoutMethod = v;
                              });
                            },
                      decoration: _fieldDecoration(label: 'Payout Method'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Payout method is required' : null,
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _submitting
                            ? null
                            : () {
                                if (_isReadOnly) {
                                  setState(() => _isReadOnly = false);
                                  return;
                                }
                                _submit();
                              },
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: ViteLoader(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(
                                _isReadOnly ? 'Change Bank' : (_bankData == null ? 'Submit' : 'Update Bank'),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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


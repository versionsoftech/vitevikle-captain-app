import 'dart:convert';
import 'package:vite_captain/widgets/vite_loader.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/screens/wallet/withdraw_request_details_screen.dart';
import 'package:vite_captain/screens/wallet/driver_withdraw_history_screen.dart';
import 'package:vite_captain/screens/bank_details_screen.dart';
import 'package:vite_captain/widgets/curved_green_app_bar.dart';

class DriverWithdrawScreen extends StatefulWidget {
  const DriverWithdrawScreen({
    super.key,
  });

  @override
  State<DriverWithdrawScreen> createState() => _DriverWithdrawScreenState();
}

class _DriverWithdrawScreenState extends State<DriverWithdrawScreen> {
  static const Color _primary = Color(0xFF369D01);
  static const Color _primaryDark = Color(0xFF246B00);
  static const Color _danger = Color(0xFFE53935);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFF6F7F9);

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();
  bool _loading = false;
  bool _hydrating = true;
  bool _historyLoading = true;

  Map<String, dynamic>? _bank;
  double _availableBalance = 0.0;
  DateTime? _lastUpdatedAt;
  List<Map<String, dynamic>> _history = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrate();
    });
  }

  void _onAmountChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountChanged);
    _amountCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    await Future.wait([
      _loadBank(),
      _loadBalance(),
      _loadHistory(),
    ]);
  }

  Future<void> _loadBalance() async {
    try {
      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (driverId.isEmpty) return;
      final res = await const ApiService().getDriverWallet(driverId: driverId);
      if (!mounted) return;
      final ok = res['success'] == true;
      final bal = ok ? (res['balance'] as num?)?.toDouble() ?? 0.0 : 0.0;
      setState(() {
        _availableBalance = bal;
        _lastUpdatedAt = DateTime.now();
      });
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
    });

    try {
      final res = await const ApiService().getDriverWithdrawHistory();
      final ok = res['success'] == true;
      final list = ok && res['data'] is List
          ? (res['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _history = list;
      });
    } catch (_) {
    } finally {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
      });
    }
  }

  Future<void> _loadBank() async {
    setState(() {
      _hydrating = true;
    });

    try {
      final session = const SessionService();
      final token = (await session.getToken())?.trim() ?? '';
      final driverId = (await session.getDriverId())?.trim() ?? '';

      if (token.isEmpty || driverId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _bank = null;
        });
        return;
      }

      final uri = Uri.parse('$baseUrl/driver/bank-details/$driverId');
      final res = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: {
            'Authorization': 'Bearer $token',
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

      final data = decoded?['data'];
      final bankMap = data is Map ? Map<String, dynamic>.from(data as Map) : null;

      if (!mounted) return;
      setState(() {
        _bank = bankMap;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bank = null;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _hydrating = false;
      });
    }
  }

  Future<void> _openChangeBank() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BankDetailsScreen(startEditing: true)),
    );
    if (changed == true && mounted) await _loadBank();
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  double _parseAmount() {
    final raw = _amountCtrl.text.trim();
    final v = double.tryParse(raw);
    return v ?? 0.0;
  }

  String _maskAccount(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '-';
    final last4 = s.length >= 4 ? s.substring(s.length - 4) : s;
    return 'XXXX$last4';
  }

  DateTime? _tryParseDate(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s).toLocal();
    } catch (_) {
      final epoch = int.tryParse(s);
      if (epoch != null && epoch > 0) {
        return DateTime.fromMillisecondsSinceEpoch(
          epoch.toString().length == 10 ? epoch * 1000 : epoch,
        ).toLocal();
      }
    }
    return null;
  }

  String _formatDate(dynamic raw) {
    final dt = _tryParseDate(raw);
    if (dt == null) return (raw ?? '').toString();
    return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
  }

  Color _statusColor(String s) {
    switch (s.trim().toLowerCase()) {
      case 'approved':
        return const Color(0xFF16A34A);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'processing':
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Widget _statusChip(String status) {
    final safe = status.trim().isEmpty ? 'pending' : status.trim().toLowerCase();
    final color = _statusColor(safe);
    final label = safe[0].toUpperCase() + safe.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11.5),
      ),
    );
  }

  Widget _openHistoryCard() {
    return _card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Withdraw History', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                SizedBox(height: 6),
                Text('View all your withdraw requests with filters', style: TextStyle(color: _muted, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DriverWithdrawHistoryScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF111827),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            icon: const Icon(Icons.table_rows_rounded, size: 18),
            label: const Text('View', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Future<void> _successPopup() async {
    if (!mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'success',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 38),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Withdraw Request Submitted',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Your request is under processing',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_loading) return;

    final amount = _parseAmount();

    if (_bank == null) {
      _snack('Bank details are not configured yet', color: _danger);
      return;
    }

    if (amount <= 0) {
      _snack('Please enter a valid amount', color: _danger);
      return;
    }

    if (amount > _availableBalance) {
      _snack('Amount cannot be greater than available balance', color: _danger);
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final res = await const ApiService().createDriverWithdrawRequest(amount: amount);
      if (!mounted) return;

      final ok = res['success'] == true;
      final msg = (res['message'] ?? '').toString().trim();

      if (!ok) {
        final display = msg.isNotEmpty ? msg : 'Failed to submit withdraw request';
        await showDialog<void>(
          context: context,
          builder: (_) {
            return AlertDialog(
              title: const Text('Withdraw Request'),
              content: Text(display),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
              ],
            );
          },
        );
        return;
      }

      _amountCtrl.clear();
      _remarksCtrl.clear();
      await _successPopup();
      await _loadHistory();
      await _loadBalance();
    } catch (_) {
      if (!mounted) return;
      _snack('Something went wrong. Please try again.', color: _danger);
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Widget _bankPreview() {
    if (_hydrating) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          children: [
            SizedBox(width: 18, height: 18, child: ViteLoader(strokeWidth: 2)),
            SizedBox(width: 12),
            Expanded(child: Text('Loading bank details...')),
          ],
        ),
      );
    }

    final b = _bank;
    if (b == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bank details not found. Please add bank details first.'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openChangeBank,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF009640),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Add Bank', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
              ),
            ),
          ],
        ),
      );
    }

    final bankName = (b['bank_name'] ?? b['bankName'] ?? '').toString().trim();
    final holderName = (b['holder_name'] ?? b['accountHolderName'] ?? '').toString().trim();
    final accountNo = (b['account_no'] ?? b['accountNumber'] ?? '').toString().trim();
    final ifsc = (b['ifsc_code'] ?? b['ifscCode'] ?? '').toString().trim();
    final status = (b['status'] ?? '').toString().trim().toLowerCase();
    final verified = status == 'approved';
    final statusLabel = verified ? 'Bank Verified' : (status == 'rejected' ? 'Rejected' : 'Under Review');
    final statusColor = verified ? const Color(0xFF009640) : (status == 'rejected' ? _danger : const Color(0xFFD97706));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Bank Account', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.22)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _kv('Bank Name', bankName.isEmpty ? '-' : bankName),
          const SizedBox(height: 10),
          _kv('Account Holder', holderName.isEmpty ? '-' : holderName),
          const SizedBox(height: 10),
          _kv('Account Number', accountNo.isEmpty ? '-' : _maskAccount(accountNo)),
          const SizedBox(height: 10),
          _kv('IFSC', ifsc.isEmpty ? '-' : ifsc),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _openChangeBank,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Change Bank', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (verified) {
                      _snack('Bank is already verified');
                      return;
                    }
                    if (status == 'rejected') {
                      _openChangeBank();
                      return;
                    }
                    _snack('Bank verification is under review');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Verify Bank', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            k,
            style: const TextStyle(color: _muted, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ),
        Expanded(
          flex: 6,
          child: Text(
            v,
            textAlign: TextAlign.right,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _quickBtn(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = _parseAmount();
    final canSubmit = !_loading && amount > 0 && amount <= _availableBalance;
    return Scaffold(
      backgroundColor: _bg,
      appBar: curvedGreenAppBar(title: 'Withdraw Money'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Transfer your earnings directly to your bank account',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55), fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_primary, _primaryDark]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 22,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Available Withdraw Balance', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                '₹ ${_availableBalance.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.20)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.verified_rounded, color: Colors.white, size: 16),
                                    SizedBox(width: 6),
                                    Text('Verified', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _lastUpdatedAt == null
                                ? 'Last updated just now'
                                : 'Last updated ${DateFormat('dd MMM, hh:mm a').format(_lastUpdatedAt!)}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _bankPreview(),
                    const SizedBox(height: 14),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Withdraw Form', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _amountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Withdraw Amount',
                              prefixIcon: const Icon(Icons.currency_rupee_rounded),
                              filled: true,
                              fillColor: const Color(0xFFF3F4F6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _remarksCtrl,
                            decoration: InputDecoration(
                              hintText: 'Remarks (Optional)',
                              prefixIcon: const Icon(Icons.notes_rounded),
                              filled: true,
                              fillColor: const Color(0xFFF3F4F6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _quickBtn('100%', () => setState(() => _amountCtrl.text = _availableBalance.toStringAsFixed(0))),
                              _quickBtn('50%', () => setState(() => _amountCtrl.text = (_availableBalance * 0.5).toStringAsFixed(0))),
                              _quickBtn('₹500', () => setState(() => _amountCtrl.text = '500')),
                              _quickBtn('₹1000', () => setState(() => _amountCtrl.text = '1000')),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Builder(
                            builder: (_) {
                              final amount = _parseAmount();
                              final fee = 0.0;
                              final finalTransfer = amount <= 0 ? 0.0 : (amount - fee);
                              return Column(
                                children: [
                                  _kv('Available Balance', '₹ ${_availableBalance.toStringAsFixed(2)}'),
                                  const SizedBox(height: 8),
                                  _kv('Processing Fee', '₹ ${fee.toStringAsFixed(2)}'),
                                  const SizedBox(height: 8),
                                  _kv('Final Transfer Amount', '₹ ${finalTransfer.toStringAsFixed(2)}'),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: const Text(
                              'Admin will review your request and process payouts to your provided bank details.',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _openHistoryCard(),
                    const SizedBox(height: 110),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: EdgeInsets.zero,
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF20B26C), Color(0xFF0E8F55)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Container(
                  alignment: Alignment.center,
                  child: _loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: ViteLoader(strokeWidth: 2, color: Theme.of(context).colorScheme.surface),
                        )
                      : const Text('Request Withdraw', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


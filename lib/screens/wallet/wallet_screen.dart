import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/screens/wallet/topup_wallet_screen.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/vehicle_type_api.dart';
import 'package:vite_captain/screens/vehicle/vehicle_details_screen.dart';

class WalletScreen extends StatefulWidget {
  final bool showBack;

  const WalletScreen({
    super.key,
    this.showBack = true,
  });

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  double _balance = 0.0;
  List<Map<String, dynamic>> _transactions = const <Map<String, dynamic>>[];
  bool _loading = true;
  Map<String, String> _vehicleNameById = const <String, String>{};
  int _selectedTab = 0;
  bool _balanceVisible = true;

  @override
  void initState() {
    super.initState();
    _loadWallet();
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

  Future<void> _loadWallet() async {
    setState(() {
      _loading = true;
    });

    try {
      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (!mounted) return;

      if (driverId.isEmpty) {
        setState(() {
          _balance = 0.0;
          _transactions = const <Map<String, dynamic>>[];
          _loading = false;
        });
        return;
      }

      final res = await const ApiService().getDriverWallet(driverId: driverId);
      if (!mounted) return;

      if (_vehicleNameById.isEmpty) {
        try {
          final vehicles = await const VehicleTypeApi().getVehicleTypes();
          if (mounted) {
            setState(() {
              _vehicleNameById = {
                for (final v in vehicles)
                  if (v.objectId.trim().isNotEmpty && v.name.trim().isNotEmpty)
                    v.objectId.trim(): v.name.trim(),
              };
            });
          }
        } catch (_) {}
      }

      final ok = res['success'] == true;
      final bal = ok ? (res['balance'] as num?)?.toDouble() ?? 0.0 : 0.0;
      final list = ok && res['transactions'] is List
          ? (res['transactions'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _balance = bal;
        _transactions = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  static final RegExp _objectIdRx = RegExp(r'\b[a-fA-F0-9]{24}\b');

  String _extractVehicleTypeIdFromNote(String note) {
    final matches = _objectIdRx.allMatches(note).map((m) => m.group(0) ?? '').where((s) => s.isNotEmpty).toList();
    if (matches.isEmpty) return '';

    for (final id in matches) {
      if (_vehicleNameById.containsKey(id)) return id;
    }
    return '';
  }

  String _formatNoteForDisplay(String note) {
    final vehicleTypeId = _extractVehicleTypeIdFromNote(note);
    if (vehicleTypeId.isEmpty) {
      if (_objectIdRx.hasMatch(note)) {
        return note.replaceAll(_objectIdRx, 'Unknown Vehicle');
      }
      return note;
    }

    final name = _vehicleNameById[vehicleTypeId]?.trim() ?? '';
    final safeName = name.isNotEmpty ? name : 'Unknown Vehicle';
    return note.replaceAll(vehicleTypeId, safeName);
  }

  String _transactionTitle(String noteRaw, String type, String source, String reason, String performedByRole, double amount) {
    // Check both note and reason fields
    final note = noteRaw.trim().toLowerCase();
    final reasonLower = reason.trim().toLowerCase();
    final typeLower = type.trim().toLowerCase();
    final performedByRoleLower = performedByRole.trim().toLowerCase();

    // IF source == "expiry_penalty" OR reason contains "penalty"
    if (source == 'expiry_penalty' || typeLower == 'expiry_penalty' || reasonLower.contains('penalty')) {
      return 'Penalty Deduction';
    }

    // IF note contains "ride_earning"
    if (note.contains('ride_earning')) {
      return 'Ride Earning';
    }

    // IF note contains "intercity"
    if (note.contains('intercity')) {
      return 'Intercity Ride Earning';
    }

    // IF note contains "parcel"
    if (note.contains('parcel')) {
      return 'Parcel Delivery Earning';
    }

    // IF note contains "commission" OR reason contains "commission"
    if (note.contains('commission') || reasonLower.contains('commission')) {
      return 'Commission Deduction';
    }

    // IF type == "credit" AND performed_by_role == "admin"
    if (typeLower == 'credit' && performedByRoleLower == 'admin') {
      return 'Admin Wallet Credit';
    }

    // IF type == "debit" AND performed_by_role == "admin"
    if (typeLower == 'debit' && performedByRoleLower == 'admin') {
      return 'Admin Wallet Debit';
    }

    // Fallback for old data without note/reason fields
    // Based on transaction type and source
    if (source == 'driver_wallet_history') {
      if (typeLower == 'credit') {
        return 'Wallet Credit';
      } else if (typeLower == 'debit') {
        return 'Wallet Debit';
      }
    }

    // ELSE
    return 'Wallet Transaction';
  }

  bool _isWithdrawalTx(Map<String, dynamic> t) {
    final note = (t['note'] ?? t['remark'] ?? '').toString().toLowerCase();
    return note == 'withdraw' || note.contains('withdraw');
  }

  bool _isCommissionDeductionTx(Map<String, dynamic> t) {
    final note = (t['note'] ?? t['remark'] ?? '').toString().toLowerCase();
    return note.contains('commission_deduction');
  }

  bool _isExpiryPenaltyTx(Map<String, dynamic> t) {
    final source = (t['source'] ?? '').toString().toLowerCase();
    final type = (t['type'] ?? '').toString().toLowerCase();
    return source == 'expiry_penalty' || type == 'expiry_penalty';
  }

  IconData _getTransactionIcon(Map<String, dynamic> t) {
    final source = (t['source'] ?? '').toString().toLowerCase();
    final type = (t['type'] ?? '').toString().toLowerCase();
    final note = (t['note'] ?? t['remark'] ?? '').toString().toLowerCase();

    if (source == 'expiry_penalty' || type == 'expiry_penalty') {
      return Icons.warning_rounded;
    }
    if (note.contains('ride') && type == 'credit') {
      return Icons.arrow_downward;
    }
    if (note.contains('topup') || note.contains('wallet topup')) {
      return Icons.account_balance_wallet;
    }
    if (note.contains('admin credit')) {
      return Icons.add_circle;
    }
    if (note.contains('commission_deduction')) {
      return Icons.percent;
    }
    if (note == 'withdraw' || note.contains('withdraw')) {
      return Icons.account_balance_wallet_outlined;
    }
    return Icons.account_balance_wallet;
  }

  Color _getTransactionColor(Map<String, dynamic> t) {
    final source = (t['source'] ?? '').toString().toLowerCase();
    final type = (t['type'] ?? '').toString().toLowerCase();
    final note = (t['note'] ?? t['remark'] ?? '').toString().toLowerCase();

    if (source == 'expiry_penalty' || type == 'expiry_penalty') {
      return Colors.red.shade900;
    }
    if (type == 'credit') {
      return Colors.green;
    }
    if (type == 'debit') {
      return Colors.red;
    }
    if (note.contains('commission_deduction')) {
      return Colors.orange;
    }
    return Colors.grey;
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_selectedTab == 0) return _transactions;

    return _transactions.where((t) {
      final type = (t['type'] ?? '').toString().toLowerCase();
      final source = (t['source'] ?? '').toString().toLowerCase();
      final isCredit = type == 'credit';
      final isDebit = type == 'debit';
      final isExpiryPenalty = source == 'expiry_penalty' || type == 'expiry_penalty';

      switch (_selectedTab) {
        case 1:
          return isCredit;
        case 2:
          return isDebit || _isCommissionDeductionTx(t) || isExpiryPenalty;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text("Wallet"),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF369D01),
                    Color(0xFF246B00),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Available Balance",
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        _balanceVisible ? "₹ ${_balance.toStringAsFixed(2)}" : "₹ ••••••••",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _balanceVisible = !_balanceVisible;
                          });
                        },
                        child: Icon(
                          _balanceVisible ? Icons.remove_red_eye : Icons.visibility_off,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TopupWalletScreen(),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, color: Colors.green),
                                SizedBox(width: 6),
                                Text("Top Up"),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.card_giftcard, color: Colors.green),
                              SizedBox(width: 6),
                              Text("Gift Card"),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _loading ? 'Loading...' : 'Balance updated just now',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "History",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TabPill(
                      label: 'All',
                      selected: _selectedTab == 0,
                      onTap: () => setState(() => _selectedTab = 0),
                    ),
                  ),
                  Expanded(
                    child: _TabPill(
                      label: 'Earnings',
                      selected: _selectedTab == 1,
                      onTap: () => setState(() => _selectedTab = 1),
                    ),
                  ),
                  Expanded(
                    child: _TabPill(
                      label: 'Deductions',
                      selected: _selectedTab == 2,
                      onTap: () => setState(() => _selectedTab = 2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadWallet,
                child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_filteredTransactions.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 48),
                            Center(
                              child: Text(
                                'No Transactions Yet',
                                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _filteredTransactions.length,
                          itemBuilder: (context, index) {
                            final t = _filteredTransactions[index];
                            final type = (t['type'] ?? '').toString().toLowerCase();
                            final source = (t['source'] ?? '').toString().toLowerCase();
                            final noteRaw = (t['note'] ?? t['remark'] ?? t['reason'] ?? '').toString();
                            final reason = (t['reason'] ?? '').toString();
                            final performedByRole = (t['performed_by_role'] ?? '').toString();
                            final amountRaw = t['amount'];
                            final amount = amountRaw is num
                                ? amountRaw.toDouble()
                                : double.tryParse(amountRaw?.toString() ?? '') ?? 0.0;
                            final title = _transactionTitle(noteRaw, type, source, reason, performedByRole, amount);
                            final subtitle = _formatNoteForDisplay(noteRaw);
                            final vehicleTypeId = _extractVehicleTypeIdFromNote(noteRaw);
                            final createdAt = t['created_at'] ?? t['createdAt'];

                            final isCredit = type == 'credit';
                            final amountText = isCredit ? '+₹${amount.toStringAsFixed(0)}' : '-₹${amount.toStringAsFixed(0)}';
                            final transactionIcon = _getTransactionIcon(t);
                            final transactionColor = _getTransactionColor(t);

                            return InkWell(
                              onTap: vehicleTypeId.isEmpty
                                  ? null
                                  : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => VehicleDetailsScreen(vehicleTypeId: vehicleTypeId),
                                          ),
                                        );
                                      },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: transactionColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        transactionIcon,
                                        color: transactionColor,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatDate(createdAt),
                                            style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                          if (subtitle.trim().isNotEmpty && subtitle.trim() != title.trim()) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w700),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Text(
                                      amountText,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: isCredit ? Colors.green : Colors.red,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1FA37A) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}


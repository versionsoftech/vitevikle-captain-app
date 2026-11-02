import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/screens/wallet/withdraw_request_details_screen.dart';
import 'package:vite_captain/services/api_service.dart';

class DriverWithdrawHistoryScreen extends StatefulWidget {
  const DriverWithdrawHistoryScreen({super.key});

  @override
  State<DriverWithdrawHistoryScreen> createState() => _DriverWithdrawHistoryScreenState();
}

class _DriverWithdrawHistoryScreenState extends State<DriverWithdrawHistoryScreen> {
  static const Color _muted = Color(0xFF6B7280);

  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  List<Map<String, dynamic>> _all = const <Map<String, dynamic>>[];

  String _status = 'all';
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
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
        _all = list;
      });
    } catch (_) {
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
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
        return const Color(0xFF009640);
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

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();

    return _all.where((w) {
      final status = (w['status'] ?? 'pending').toString().trim().toLowerCase();
      if (_status != 'all' && status != _status) return false;

      final dt = _tryParseDate(w['created_at'] ?? w['date'] ?? w['requestedAt'] ?? w['createdAt']);
      if (_range != null && dt != null) {
        final start = DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
        final end = DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59);
        if (dt.isBefore(start) || dt.isAfter(end)) return false;
      }

      if (q.isEmpty) return true;
      final txId = (w['transaction_id'] ?? w['transactionId'] ?? w['requestId'] ?? '').toString().toLowerCase();
      final bank = (w['bank_name'] ?? w['bankName'] ?? '').toString().toLowerCase();
      final holder = (w['holder_name'] ?? w['accountHolderName'] ?? '').toString().toLowerCase();
      return txId.contains(q) || bank.contains(q) || holder.contains(q);
    }).toList();
  }

  Future<void> _pickRange() async {
    final initialDateRange = _range ??
        DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 30)),
          end: DateTime.now(),
        );

    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initialDateRange,
    );

    if (!mounted) return;
    setState(() {
      _range = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Withdraw History'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by Txn ID / Bank / Holder',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _status,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Status')),
                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        DropdownMenuItem(value: 'processing', child: Text('Processing')),
                        DropdownMenuItem(value: 'approved', child: Text('Approved')),
                        DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _status = v;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickRange,
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range_rounded),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _range == null
                                    ? 'Date Range'
                                    : '${DateFormat('dd MMM').format(_range!.start)} - ${DateFormat('dd MMM').format(_range!.end)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (_range != null)
                              IconButton(
                                onPressed: () => setState(() => _range = null),
                                icon: const Icon(Icons.close_rounded),
                                splashRadius: 18,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
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
                  child: _loading
                      ? const Center(child: ViteLoader(strokeWidth: 2))
                      : list.isEmpty
                          ? const Center(
                              child: Text(
                                'No withdraw requests found',
                                style: TextStyle(color: _muted, fontWeight: FontWeight.w800),
                              ),
                            )
                          : Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                                  child: Row(
                                    children: const [
                                      SizedBox(
                                        width: 40,
                                        child: Text(
                                          'S/N',
                                          style: TextStyle(color: _muted, fontWeight: FontWeight.w900, fontSize: 11),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          'Txn ID',
                                          style: TextStyle(color: _muted, fontWeight: FontWeight.w900, fontSize: 11),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          'Amount',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(color: _muted, fontWeight: FontWeight.w900, fontSize: 11),
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      SizedBox(
                                        width: 92,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            'Status',
                                            style: TextStyle(color: _muted, fontWeight: FontWeight.w900, fontSize: 11),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: ListView.separated(
                                    itemCount: list.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (_, i) {
                                      final w = list[i];
                                      final status = (w['status'] ?? 'pending').toString();
                                      final txId = (w['transaction_id'] ?? w['transactionId'] ?? w['requestId'] ?? '').toString().trim();
                                      final amountRaw = w['amount_value'] ?? w['amount'];
                                      final amount = amountRaw is num ? amountRaw.toDouble() : double.tryParse(amountRaw?.toString() ?? '') ?? 0.0;
                                      final bankName = (w['bank_name'] ?? w['bankName'] ?? '').toString().trim();
                                      final createdAt = _formatDate(w['created_at'] ?? w['date'] ?? w['requestedAt'] ?? w['createdAt']);
                                      final serial = '#${(i + 1).toString().padLeft(3, '0')}';

                                      return InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => WithdrawRequestDetailsScreen(withdraw: w),
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  SizedBox(
                                                    width: 40,
                                                    child: Text(
                                                      serial,
                                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 4,
                                                    child: Text(
                                                      txId.isEmpty ? '-' : txId,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                      '\u20B9 ${amount.toStringAsFixed(0)}',
                                                      textAlign: TextAlign.right,
                                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  SizedBox(
                                                    width: 92,
                                                    child: Align(
                                                      alignment: Alignment.centerRight,
                                                      child: _statusChip(status),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${bankName.isEmpty ? 'Bank Transfer' : bankName} • $createdAt',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: _muted, fontWeight: FontWeight.w700, fontSize: 11.5),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
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


import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WithdrawRequestDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> withdraw;

  static const Color _primary = Color(0xFF009640);

  const WithdrawRequestDetailsScreen({
    super.key,
    required this.withdraw,
  });

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

  String _formatDate(dynamic raw, {String pattern = 'dd MMM yyyy, hh:mm a'}) {
    final dt = _tryParseDate(raw);
    if (dt == null) return (raw ?? '').toString();
    return DateFormat(pattern).format(dt);
  }

  String _maskAccount(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '-';
    if (s.startsWith('XXXX')) return s;
    final last4 = s.length >= 4 ? s.substring(s.length - 4) : s;
    return 'XXXX$last4';
  }

  Color _statusColor(String s) {
    switch (s.trim().toLowerCase()) {
      case 'approved':
        return const Color(0xFF009640);
      case 'rejected':
        return Colors.red;
      case 'processing':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  Widget _chip(String status) {
    final s = status.trim().isEmpty ? 'pending' : status.trim().toLowerCase();
    final c = _statusColor(s);
    final text = s[0].toUpperCase() + s.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              k,
              style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? '-' : v,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactionId = (withdraw['transaction_id'] ?? withdraw['transactionId'] ?? withdraw['requestId'] ?? '').toString().trim();
    final requestId = (withdraw['request_id'] ?? withdraw['requestId'] ?? '').toString().trim();

    final bankName = (withdraw['bank_name'] ?? withdraw['bankName'] ?? '').toString().trim();
    final holder = (withdraw['accountHolderName'] ?? withdraw['account_holder_name'] ?? '').toString().trim();
    final account = _maskAccount(
      withdraw['account_number'] ??
          withdraw['accountNumber'] ??
          withdraw['account_no'] ??
          withdraw['accountNo'] ??
          withdraw['bank_account_no'] ??
          withdraw['bankAccountNo'],
    );
    final ifsc = (withdraw['ifscCode'] ??
            withdraw['ifsc_code'] ??
            withdraw['ifsc'] ??
            withdraw['ifscCodeValue'] ??
            '')
        .toString()
        .trim();

    final method = (withdraw['payment_method'] ?? withdraw['paymentMethod'] ?? '').toString().trim();
    final status = (withdraw['status'] ?? 'pending').toString().trim();

    final amountRaw = withdraw['amount_value'] ?? withdraw['amount'] ?? 0;
    final amountNum = amountRaw is num ? amountRaw.toDouble() : double.tryParse(amountRaw.toString()) ?? 0.0;
    final amountText = '₹ ${amountNum.toStringAsFixed(0)}';

    final requestedAt = withdraw['created_at'] ?? withdraw['date'] ?? withdraw['requestedAt'] ?? '';
    final approvedAt = withdraw['approved_at'] ?? withdraw['approvedAt'] ?? '';
    final remark = (withdraw['remarks'] ?? withdraw['remark'] ?? withdraw['adminRemark'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(22),
          ),
          child: AppBar(
            title: const Text('Withdraw Details'),
            centerTitle: true,
            elevation: 0,
            backgroundColor: _primary,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Amount', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w800, fontSize: 12)),
                          const SizedBox(height: 6),
                          Text(amountText, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    _chip(status),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 14,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Receipt', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 6),
                        _kv('Transaction ID', transactionId),
                        _kv('Request ID', requestId),
                        _kv('Payment Method', method),
                        _kv('Bank Name', bankName),
                        _kv('Account Holder', holder),
                        _kv('Account Number', account),
                        _kv('IFSC Code', ifsc),
                        _kv('Request Time', _formatDate(requestedAt)),
                        _kv('Approved Time', approvedAt.toString().trim().isEmpty ? '-' : _formatDate(approvedAt)),
                        if (remark.isNotEmpty) _kv('Admin Remark', remark),
                      ],
                    ),
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

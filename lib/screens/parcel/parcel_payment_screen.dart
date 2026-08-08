import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/global_payment_popup.dart';
import 'package:vite_captain/widgets/payment_received_popup.dart';

class ParcelPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> parcel;

  const ParcelPaymentScreen({
    super.key,
    required this.parcel,
  });

  @override
  State<ParcelPaymentScreen> createState() => _ParcelPaymentScreenState();
}

class _ParcelPaymentScreenState extends State<ParcelPaymentScreen> {
  static const Color _green = Color(0xFF369D01);

  bool _loading = false;
  bool _completing = false;
  Timer? _paymentStatusTimer;

  String _asTrimmed(dynamic v) => v == null ? '' : v.toString().trim();

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return const <String, dynamic>{};
  }

  Future<void> _refreshWalletCache() async {
    try {
      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (driverId.isEmpty) return;
      final res = await const ApiService().getDriverWallet(driverId: driverId);
      if (res['success'] == true) {
        final bal = (res['balance'] as num?)?.toDouble() ?? 0.0;
        await const SessionService().saveWalletBalance(bal);
      }
    } catch (_) {}
  }

  Future<void> _showCommissionSnackFromResponse(Map<String, dynamic> resp) async {
    try {
      final raw = _asMap(resp['raw']);
      final commission = _asMap(raw['commission']);
      final applied = commission['applied'] == true;
      if (!applied) return;
      final amount = _asDouble(commission['commission'] ?? commission['amount']);
      if (amount <= 0) return;

      await _refreshWalletCache();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black.withOpacity(0.92),
          content: Text('Commission ₹${amount.toStringAsFixed(0)} deducted from your wallet'),
        ),
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final paymentType = _asTrimmed(widget.parcel['payment_type'] ?? widget.parcel['paymentType'] ?? 'COD');
    if (paymentType.toLowerCase() == 'wallet') {
      _startPaymentStatusPolling();
    }
  }

  @override
  void dispose() {
    _paymentStatusTimer?.cancel();
    super.dispose();
  }

  void _startPaymentStatusPolling() {
    final parcelId = _asTrimmed(widget.parcel['_id'] ?? widget.parcel['id']);
    if (parcelId.isEmpty) return;

    print('PAYMENT STATUS POLLING STARTED for parcel: $parcelId');

    _paymentStatusTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        print('PAYMENT STATUS API HIT for parcel: $parcelId');
        final resp = await DioClient.dio.get('$baseUrl/api/driver/payment-status/$parcelId');
        print('PAYMENT STATUS RESPONSE for parcel: ${resp.data}');

        if (resp.data is! Map) return;
        final data = resp.data as Map<String, dynamic>;
        final paymentStatus = _asTrimmed(data['payment_status']);

        if (paymentStatus == 'user_confirmed' || paymentStatus == 'completed') {
          print('PAYMENT POPUP CONDITION MATCHED for parcel: $parcelId ($paymentStatus)');
          timer.cancel();

final prefs = await SharedPreferences.getInstance();
          final popupKey = 'payment_popup_shown_$parcelId';
          final alreadyShown = prefs.getBool(popupKey) ?? false;

          if (!alreadyShown) {
            final amount = _asDouble(data['amount']);
            final commissionAmount = _asDouble(data['commission_amount']);
            final commissionDeducted = commissionAmount > 0;

            print('DRIVER PAYMENT POPUP SHOWN for parcel: $parcelId');
            await showGlobalPaymentPopup(
              amount: amount,
              commissionAmount: commissionAmount,
              commissionDeducted: commissionDeducted,
            );
            print('PAYMENT POPUP CLOSED BY DRIVER for parcel: $parcelId');

            await prefs.setBool(popupKey, true);
            print('NOW OPENING REVIEW SCREEN for parcel: $parcelId');
            if (mounted) {
              _showPaidBottomSheet();
            }
          }
        }
      } catch (_) {
        // Continue polling on error
      }
    });
  }

  Future<void> _handleReceived() async {
    if (_completing) return;
    final parcelId = _asTrimmed(widget.parcel['_id'] ?? widget.parcel['id']);
    if (parcelId.isEmpty) return;

    setState(() => _completing = true);
    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) return;

      final resp = await const ApiService().completeParcelRide(
        token: token,
        parcelId: parcelId,
      );

      await _showCommissionSnackFromResponse(resp is Map<String, dynamic> ? resp : <String, dynamic>{});

      if (!mounted) return;
      final ok = resp['success'] == true || resp['status'] == true || resp['success'] == 'true' || resp['status'] == 'true';
      if (!ok) {
        final rawMsg = (resp['message'] ?? 'Failed to complete ride').toString();
        final msg = rawMsg.toLowerCase().contains('unable to complete ride') ? 'Failed to complete ride' : rawMsg;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ride Completed'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _completing = false);
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _showPaidBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ParcelPaidBottomSheet(parcel: widget.parcel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parcel = widget.parcel;
    final paymentType = _asTrimmed(parcel['payment_type'] ?? parcel['paymentType'] ?? 'COD');
    final isWallet = paymentType.toLowerCase() == 'wallet';
    final priceRaw = parcel['price'];
    final price = priceRaw is num ? priceRaw.toDouble() : double.tryParse(_asTrimmed(priceRaw)) ?? 0.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text('Payment', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _green.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      '₹${price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: _green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isWallet ? 'Wallet Payment' : 'Cash Payment',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (isWallet)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Waiting for user to confirm payment...',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (isWallet) const SizedBox(height: 24),
              if (!isWallet)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _completing ? null : _handleReceived,
                    child: _completing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Complete Ride', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ParcelPaidBottomSheet extends StatelessWidget {
  final Map<String, dynamic> parcel;

  const ParcelPaidBottomSheet({
    super.key,
    required this.parcel,
  });

  @override
  Widget build(BuildContext context) {
    final priceRaw = parcel['price'];
    final price = priceRaw is num ? priceRaw.toDouble() : double.tryParse(priceRaw?.toString() ?? '') ?? 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 5,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Payment Received!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${price.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF369D01),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}


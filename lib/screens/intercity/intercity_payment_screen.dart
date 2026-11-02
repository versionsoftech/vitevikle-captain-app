import 'dart:async';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vite_captain/models/intercity_request.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/global_payment_popup.dart';
import 'package:vite_captain/widgets/payment_received_popup.dart';
import 'package:vite_captain/screens/activity/activity_screen.dart';

class IntercityPaymentScreen extends StatefulWidget {
  final IntercityRequestModel ride;

  const IntercityPaymentScreen({
    super.key,
    required this.ride,
  });

  @override
  State<IntercityPaymentScreen> createState() => _IntercityPaymentScreenState();
}

class _IntercityPaymentScreenState extends State<IntercityPaymentScreen> {
  static const Color _green = Color(0xFF009640);

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
    print('Wallet Deduction Method Called');
    try {
      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (driverId.isEmpty) return;
      
      // Get wallet before deduction
      final beforeRes = await const ApiService().getDriverWallet(driverId: driverId);
      if (beforeRes['success'] == true) {
        final beforeBal = (beforeRes['balance'] as num?)?.toDouble() ?? 0.0;
        print('Wallet Before: $beforeBal');
      }
      
      final res = await const ApiService().getDriverWallet(driverId: driverId);
      if (res['success'] == true) {
        final bal = (res['balance'] as num?)?.toDouble() ?? 0.0;
        print('Wallet After: $bal');
        await const SessionService().saveWalletBalance(bal);
      }
    } catch (e) {
      print('Exception in wallet refresh: $e');
    }
  }

  Future<void> _showCommissionSnackFromResponse(Map<String, dynamic> resp) async {
    try {
      final raw = _asMap(resp['raw']);
      final commission = _asMap(raw['commission']);
      final applied = commission['applied'] == true;
      if (!applied) return;
      final amount = _asDouble(commission['commission'] ?? commission['amount']);
      print('Commission: $amount');
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
    } catch (e) {
      print('Exception in commission snack: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.ride.paymentType.toLowerCase() == 'wallet') {
      _startPaymentStatusPolling();
    }
  }

  @override
  void dispose() {
    _paymentStatusTimer?.cancel();
    super.dispose();
  }

  void _startPaymentStatusPolling() {
    final rideId = _asTrimmed(widget.ride.id);
    if (rideId.isEmpty) return;

    print('PAYMENT STATUS POLLING STARTED for intercity ride: $rideId');

    _paymentStatusTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        print('PAYMENT STATUS API HIT for intercity ride: $rideId');
        final resp = await DioClient.dio.get('$baseUrl/api/driver/payment-status/$rideId');
        print('PAYMENT STATUS RESPONSE for intercity ride: ${resp.data}');

        if (resp.data is! Map) return;
        final data = resp.data as Map<String, dynamic>;
        final paymentStatus = _asTrimmed(data['payment_status']);

        if (paymentStatus == 'waiting_confirmation' || paymentStatus == 'user_confirmed' || paymentStatus == 'completed') {
          print('PAYMENT POPUP CONDITION MATCHED for intercity ride: $rideId ($paymentStatus)');
          timer.cancel();

final prefs = await SharedPreferences.getInstance();
          final popupKey = 'payment_popup_shown_$rideId';
          final alreadyShown = prefs.getBool(popupKey) ?? false;

          if (!alreadyShown) {
            final amount = _asDouble(data['amount']);
            final commissionAmount = _asDouble(data['commission_amount']);
            final commissionDeducted = commissionAmount > 0;

            print('DRIVER PAYMENT POPUP SHOWN for intercity ride: $rideId');
            await showGlobalPaymentPopup(
              amount: amount,
              commissionAmount: commissionAmount,
              commissionDeducted: commissionDeducted,
            );
            print('PAYMENT POPUP CLOSED BY DRIVER for intercity ride: $rideId');

            await prefs.setBool(popupKey, true);
            print('NOW OPENING REVIEW SCREEN for intercity ride: $rideId');
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
    print('========== INTERCITY CASH PAYMENT START ==========');
    print('FILE: intercity_payment_screen.dart');
    print('METHOD: _handleReceived');
    print('RIDE ID: ${widget.ride.id}');
    print('PAYMENT TYPE: ${widget.ride.paymentType}');
    print('PAYMENT RECEIVED BUTTON CLICKED');
    
    if (_completing) return;
    final rideId = _asTrimmed(widget.ride.id);
    if (rideId.isEmpty) return;

    print('LOADER: Button ViteLoader opened');
    setState(() => _completing = true);
    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (token.isEmpty || driverId.isEmpty) {
        print('ERROR: Token or Driver ID empty, stopping loader');
        if (mounted) setState(() => _completing = false);
        return;
      }

      final isWallet = widget.ride.paymentType.toLowerCase() == 'wallet';
      print('PAYMENT TYPE CHECK: isWallet=$isWallet');
      print('API CALL: confirmCashReceived with rideType=intercity');
      print('API REQUEST SENT');
      
      // Use the same confirmCashReceived API that Normal Cash and Parcel Cash use
      // This ensures consistent wallet deduction flow
      final resp = isWallet
          ? await const ApiService().receiveIntercityPayment(
              token: token,
              rideId: rideId,
            )
          : await const ApiService().confirmCashReceived(
              token: token,
              rideId: rideId,
              rideType: 'intercity',
            );

      print('API RESPONSE RECEIVED');
      print('API RESPONSE: $resp');
      print('COMMISSION DATA: ${resp['commission']}');
      
      await _showCommissionSnackFromResponse(resp is Map<String, dynamic> ? resp : <String, dynamic>{});

      if (!mounted) {
        print('WIDGET NOT MOUNTED, STOPPING LOADER');
        return;
      }
      
      final ok = resp['success'] == true || resp['status'] == true || resp['success'] == 'true' || resp['status'] == 'true';
      if (!ok) {
        print('API FAILED RESPONSE');
        final rawMsg = (resp['message'] ?? 'Failed to receive payment').toString();
        final msg = rawMsg.toLowerCase().contains('payment not yet confirmed') ? 'Payment not yet confirmed by user' : rawMsg;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        print('API FAILED: $msg');
        print('STOPPING LOADER ON FAILURE');
        setState(() => _completing = false);
        return;
      }

      print('SUCCESS RESPONSE');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment Received ✅'),
          backgroundColor: const Color(0xFF009640),
          behavior: SnackBarBehavior.floating,
        ),
      );
      print('NAVIGATION: Navigating to ActivityScreen');
      print('STOPPING LOADER BEFORE NAVIGATION');
      setState(() => _completing = false);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ActivityScreen()),
        (route) => false,
      );
      print('LOADER: Button ViteLoader closed');
      print('========== INTERCITY CASH PAYMENT END ==========');
    } catch (e) {
      print('EXCEPTION CAUGHT: $e');
      print('STOPPING LOADER ON EXCEPTION');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
      setState(() => _completing = false);
    }
  }

  void _showPaidBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => IntercityPaidBottomSheet(ride: widget.ride),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final isWallet = ride.paymentType.toLowerCase() == 'wallet';
    final fare = ride.price > 0 ? ride.price : ride.bidPrice;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                      '\u20B9${fare.toStringAsFixed(0)}',
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
                            child: ViteLoader(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Complete Ride', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              if (isWallet)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _completing ? null : _handleReceived,
                    child: _completing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: ViteLoader(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Received', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class IntercityPaidBottomSheet extends StatelessWidget {
  final IntercityRequestModel ride;

  const IntercityPaidBottomSheet({
    super.key,
    required this.ride,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
          const Icon(Icons.check_circle, color: const Color(0xFF009640), size: 64),
          const SizedBox(height: 16),
          const Text(
            'Payment Received!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF009640),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${(ride.price > 0 ? ride.price : ride.bidPrice).toStringAsFixed(0)}',
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
                backgroundColor: const Color(0xFF009640),
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


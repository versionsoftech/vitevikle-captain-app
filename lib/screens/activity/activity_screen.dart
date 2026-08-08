import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/models/intercity_request.dart';
import 'package:vite_captain/screens/home/intercity_ride_map_screen.dart';
import 'package:vite_captain/screens/home/driver_give_review_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vite_captain/screens/intercity/intercity_chat_screen.dart';
import 'package:vite_captain/screens/chat/ride_chat_screen.dart';
import 'package:vite_captain/screens/parcel/parcel_drop_map_screen.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/services/parcel_activity_state.dart';
import 'package:vite_captain/services/global_payment_popup.dart';

class ActivityScreen extends StatefulWidget {
  final int initialIndex;

  const ActivityScreen({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Future<List<Map<String, dynamic>>>? _ridesFuture;
  Future<List<Map<String, dynamic>>>? _parcelUpcomingFuture;
  Future<List<Map<String, dynamic>>>? _parcelCompletedFuture;
  Future<List<Map<String, dynamic>>>? _parcelCancelledFuture;
  String _driverId = '';

  ParcelActivityState? _parcelActivityState;

  List<Map<String, dynamic>> _upcomingParcelsCache = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _completedParcelsCache = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _cancelledParcelsCache = <Map<String, dynamic>>[];

  final Set<String> _deliveryVerifiedParcelIds = <String>{};
  final Set<String> _parcelPaymentPendingIds = <String>{};
  final Set<String> _parcelWaitingPaymentIds = <String>{};
  final Set<String> _parcelAutoCompletingIds = <String>{};
  final Set<String> _confirmCashProcessingParcelIds = <String>{};
  final Set<String> _expiryCheckedRideIds = <String>{};
  final Set<String> _expiryCheckedParcelIds = <String>{};
  Timer? _expiryCheckTimer;

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  void _startParcelWalletPaymentPolling({
    required String parcelId,
    required Map<String, dynamic> parcel,
  }) {
    if (parcelId.isEmpty) return;
    if (_parcelWaitingPaymentIds.contains(parcelId) == false) {
      _parcelWaitingPaymentIds.add(parcelId);
    }

    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_parcelAutoCompletingIds.contains(parcelId)) {
        timer.cancel();
        return;
      }

      try {
        final resp = await DioClient.dio.get('$baseUrl/api/driver/payment-status/$parcelId');
        if (resp.data is! Map) return;
        final data = Map<String, dynamic>.from(resp.data as Map);
        final paymentStatus = _text(data['payment_status']).trim().toLowerCase();

        final paymentType = _text(parcel['payment_type'] ?? parcel['paymentType'] ?? parcel['payment_method'] ?? parcel['paymentMethod'] ?? 'COD').toLowerCase();
        final isWallet = paymentType == 'wallet';

        if (paymentStatus == 'user_confirmed' || paymentStatus == 'completed' || paymentStatus == 'paid') {
          timer.cancel();

          final prefs = await SharedPreferences.getInstance();
          final popupKey = 'payment_popup_shown_$parcelId';
          final alreadyShown = prefs.getBool(popupKey) ?? false;
          if (!alreadyShown) {
            final amount = _asDouble(data['amount']);
            final commissionAmount = _asDouble(data['commission_amount']);
            final commissionDeducted = commissionAmount > 0;

            await showGlobalPaymentPopup(
              amount: amount,
              commissionAmount: commissionAmount,
              commissionDeducted: commissionDeducted,
            );
            await prefs.setBool(popupKey, true);
          }

          if (isWallet) {
            await _autoCompleteWalletParcel(parcelId: parcelId, parcel: parcel);
          } else {
            if (!mounted) return;
            setState(() {
              _parcelWaitingPaymentIds.remove(parcelId);
            });
          }
        }
      } catch (_) {
        // keep polling
      }
    });
  }

  void _startExpiryCheckPolling() {
    print("PARCEL EXPIRY TIMER STARTED");
    print("INTERCITY EXPIRY TIMER STARTED");
    _expiryCheckTimer?.cancel();
    _expiryCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      print("PARCEL EXPIRY CHECK");
      print("INTERCITY EXPIRY CHECK");
      await _checkAndExpireRides();
    });
  }

  Future<void> _checkAndExpireRides() async {
    try {
      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (driverId.isEmpty) return;

      // Check intercity rides
      final List<Map<String, dynamic>> rides =
          _ridesFuture != null
              ? await _ridesFuture!
              : <Map<String, dynamic>>[];
      for (final Map<String, dynamic> ride in rides) {
        final rideId = _text(ride['_id'] ?? ride['id'] ?? ride['ride_id']);
        if (rideId.isEmpty) continue;
        if (_expiryCheckedRideIds.contains(rideId)) continue;

        final status = _text(ride['status'] ?? '').toLowerCase();
        if (status == 'accepted' || status == 'assigned') {
          try {
            print("INTERCITY EXPIRY API CALL");
            final url = '$baseUrl/check-expire-intercity';
            print("REQUEST URL: $url");
            print("REQUEST ID: $rideId");
            final resp = await DioClient.dio.post(
              url,
              data: {'rideId': rideId},
            );
            print("RESPONSE: ${resp.data}");
            if (resp.data is Map) {
              final data = Map<String, dynamic>.from(resp.data as Map);
              final status = _text(data['data']?['status']);
              print("EXPIRY API RESPONSE => ${resp.data}");
              if (_isTrue(data['success']) && status == 'expired') {
                print("RIDE STATUS CHANGED TO EXPIRED");
                print("EXPIRED RIDE ID: $rideId");
                print("OLD STATUS: accepted");
                print("NEW STATUS: expired");
                print("TAB MOVED TO: Cancelled/Expired");
                _expiryCheckedRideIds.add(rideId);
                print("REFRESHING ACTIVITY SCREEN");
                _ridesFuture = _fetchAllRides();
                _parcelUpcomingFuture = _fetchUpcomingParcels();
                _parcelCompletedFuture = _fetchCompletedParcels();
                _parcelCancelledFuture = _fetchCancelledParcels();
                if (mounted) setState(() {});
                print("MOVING RIDE TO EXPIRED TAB");
                _showExpiryPopup();
              }
            }
          } catch (_) {}
        }
      }

      // Check parcel rides
      print("PARCEL EXPIRE CHECK STARTED");
      final parcels = _parcelUpcomingFuture != null
          ? await _parcelUpcomingFuture!
          : <Map<String, dynamic>>[];
      print("PARCEL EXPIRE RECORD FOUND: ${parcels.length} parcels");
      for (final parcel in parcels) {
        final parcelId = _parcelId(parcel);
        if (parcelId.isEmpty) continue;
        if (_expiryCheckedParcelIds.contains(parcelId)) continue;

        final status = _text(parcel['status'] ?? '').toLowerCase();
        if (status == 'accepted') {
          try {
            print("PARCEL EXPIRY API CALL");
            final url = '$baseUrl/check-expire-parcel';
            print("REQUEST URL: $url");
            print("REQUEST ID: $parcelId");
            final resp = await DioClient.dio.post(
              url,
              data: {'parcelId': parcelId},
            );
            print("RESPONSE: ${resp.data}");

            if (resp.data is Map) {
              final data = Map<String, dynamic>.from(resp.data as Map);
              final status = _text(data['data']?['status']);
              print("EXPIRY API RESPONSE => ${resp.data}");
              if (_isTrue(data['success']) && status == 'expired') {
                print("PARCEL EXPIRE UPDATED");
                print("RIDE STATUS CHANGED TO EXPIRED");
                print("EXPIRED PARCEL ID: $parcelId");
                print("OLD STATUS: accepted");
                print("NEW STATUS: expired");
                print("TAB MOVED TO: Cancelled/Expired");
                _expiryCheckedParcelIds.add(parcelId);
                print("REFRESHING ACTIVITY SCREEN");
                _ridesFuture = _fetchAllRides();
                _parcelUpcomingFuture = _fetchUpcomingParcels();
                _parcelCompletedFuture = _fetchCompletedParcels();
                _parcelCancelledFuture = _fetchCancelledParcels();
                if (mounted) setState(() {});
                print("MOVING PARCEL TO EXPIRED TAB");
                _showExpiryPopup();
              }
            }
          } catch (_) {}
        }
      }
      print("PARCEL EXPIRE CHECK COMPLETE");
    } catch (_) {}
  }

  Future<void> _showExpiryPopup() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Material(
        color: Colors.transparent,
        child: Dialog(
          backgroundColor: Colors.white,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 72,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Ride Expired",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  "This booking expired because pickup was not started within the allowed time.\nA warning has been added to your account.",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text("OK"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _autoCompleteWalletParcel({
    required String parcelId,
    required Map<String, dynamic> parcel,
  }) async {
    if (_parcelAutoCompletingIds.contains(parcelId)) return;
    setState(() {
      _parcelAutoCompletingIds.add(parcelId);
    });

    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) return;
      final resp = await const ApiService().completeParcelRide(token: token, parcelId: parcelId);
      final ok = _isTrue(resp['success']) || _isTrue(resp['status']);
      if (!ok) return;

      if (!mounted) return;
      setState(() {
        parcel['status'] = 'COMPLETED';
        parcel['payment_status'] = 'completed';
        _deliveryVerifiedParcelIds.remove(parcelId);
        _parcelWaitingPaymentIds.remove(parcelId);

        _upcomingParcelsCache = _upcomingParcelsCache
            .where((e) => _parcelId(e) != parcelId)
            .toList(growable: false);

        final alreadyInCompleted = _completedParcelsCache.any((e) => _parcelId(e) == parcelId);
        if (!alreadyInCompleted) {
          _completedParcelsCache.insert(0, { ...parcel });
        }
        _completedParcelsCache.sort((a, b) => _completedAtOf(b).compareTo(_completedAtOf(a)));
        _parcelUpcomingFuture = Future.value(_upcomingParcelsCache);
        _parcelCompletedFuture = Future.value(_completedParcelsCache);
      });

      _tabController.animateTo(1);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _parcelAutoCompletingIds.remove(parcelId);
        });
      } else {
        _parcelAutoCompletingIds.remove(parcelId);
      }
    }
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
      final commission = _asMap(resp['commission']);
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

  bool _isTrue(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'success';
  }

  DateTime _completedAtOf(Map<String, dynamic> item) {
    final raw = item['completedAt'] ?? item['completed_at'] ?? item['completed_at_time'] ?? item['deliveredAt'] ?? item['delivered_at'];
    if (raw is DateTime) return raw;
    if (raw is num) {
      final v = raw.toInt();
      final ms = v > 1000000000000 ? v : v * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    final s = _text(raw);
    final parsed = DateTime.tryParse(s);
    if (parsed != null) return parsed;
    final fallback = _text(item['updatedAt'] ?? item['updated_at'] ?? item['createdAt'] ?? item['created_at']);
    return DateTime.tryParse(fallback) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _parcelId(Map<String, dynamic> parcel) => _text(
        parcel['_id'] ??
            parcel['id'] ??
            parcel['parcel_id'] ??
            parcel['parcelId'] ??
            parcel['booking_id'] ??
            parcel['bookingId'],
      );

  String _deliveryOtpFromParcel(Map<String, dynamic> parcel) {
    return _text(
      parcel['delivery_otp'] ??
          parcel['deliveryOtp'] ??
          parcel['drop_otp'] ??
          parcel['dropOtp'] ??
          parcel['otp'] ??
          parcel['pickup_otp'] ??
          parcel['pickupOtp'],
    );
  }

  Future<void> _showDeliveryOtpDialog(Map<String, dynamic> parcel) async {
    final id = _parcelId(parcel);
    if (id.isEmpty) return;

    final expected = _deliveryOtpFromParcel(parcel);
    final controller = TextEditingController();
    bool verifying = false;
    bool dialogClosed = false;

    Future<void> verifyNow(BuildContext dialogContext, void Function(void Function()) setDialogState) async {
      if (verifying) return;
      final otp = controller.text.trim();
      if (otp.length < 4) return;

      print("STEP 1 OTP SUBMIT: Starting delivery OTP verification");

      try {
        if (!dialogClosed) {
          setDialogState(() => verifying = true);
        }
      } catch (_) {}

      try {
        print("STEP 2 VERIFY OTP: Verifying OTP locally");
        final ok = expected.isEmpty ? otp.isNotEmpty : otp == expected;
        if (!ok) {
          print("ERROR: Invalid OTP");
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid OTP')));
          return;
        }

        print("STEP 3 API CALL START: No API call for delivery OTP (local verification)");
        print("STEP 3 API SUCCESS: Local verification completed");

        print("STEP 4 VERIFY RESULT TRUE: Delivery OTP verification successful");

        try {
          HapticFeedback.lightImpact();
        } catch (_) {}

        // STEP 5: CLOSE OTP POPUP
        print("STEP 5 CLOSE DIALOG: Closing delivery OTP dialog");
        dialogClosed = true;
        if (Navigator.of(dialogContext).canPop()) {
          Navigator.of(dialogContext).pop(true);
        }
        print("STEP 6 DIALOG CLOSED: Delivery OTP dialog closed");

        // Wait before showing success dialog
        await Future.delayed(const Duration(milliseconds: 150));

        // STEP 7: SHOW SUCCESS DIALOG
        print("STEP 7 SHOW SUCCESS: Showing success dialog");
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            // AUTO CLOSE AFTER 2 SECONDS
            Future.delayed(const Duration(seconds: 2), () {
              print("STEP 8 AUTO CLOSE SUCCESS: Auto-closing success dialog");
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
                print("STEP 8 SUCCESS CLOSED: Success dialog closed");
              }
            });

            return Material(
              color: Colors.transparent,
              child: Dialog(
                backgroundColor: Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 72,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Parcel Delivered Successfully",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "The parcel has been delivered successfully and payment confirmation is pending.",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            "OK",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        // STEP 8: UPDATE UI
        print("STEP 8 UPDATE STATE: Updating delivery verified state");
        if (!mounted) return;
        setState(() {
          _deliveryVerifiedParcelIds.add(id);
          _parcelWaitingPaymentIds.add(id);
          _upcomingParcelsCache = _upcomingParcelsCache
              .map((e) {
                final pid = _text(e['_id'] ?? e['id']);
                if (pid == id) {
                  return {
                    ...e,
                  };
                }
                return e;
              })
              .toList(growable: false);
          _parcelUpcomingFuture = Future.value(_upcomingParcelsCache);
        });
        print("STEP 8 NAVIGATION COMPLETE: Delivery OTP flow completed");

        // STEP 5: MOVE PARCEL TO PAYMENT PENDING (BACKEND)
        try {
          final token = (await const SessionService().getToken())?.trim() ?? '';
          if (token.isNotEmpty) {
            print('OTP Verified Successfully');
            print('Updating Parcel Status');
            print('New Status: payment_pending');
            print('New Payment Status: pending');
            final resp = await const ApiService().markParcelPaymentPending(
              token: token,
              parcelId: id,
            );
            print('MongoDB Update Success: ${resp['success']}');
            if (mounted && (_isTrue(resp['success']) || _isTrue(resp['status']))) {
              setState(() {
                _parcelPaymentPendingIds.add(id);
              });
            }
          }
        } catch (_) {
          print('MongoDB Update Failed');
        }

        // STEP 6: START WAITING/POLLING FOR PAYMENT
        try {
          final paymentType = _text(parcel['payment_type'] ?? parcel['paymentType'] ?? parcel['payment_method'] ?? parcel['paymentMethod'] ?? 'COD').toLowerCase();
          if (paymentType == 'wallet' || paymentType == 'cash' || paymentType == 'cod') {
            _startParcelWalletPaymentPolling(parcelId: id, parcel: parcel);
          }
        } catch (_) {}
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP verification failed')));
      } finally {
        try {
          if (!dialogClosed) {
            setDialogState(() => verifying = false);
          }
        } catch (_) {}
      }
    }

    await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.92, end: 1.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: Opacity(opacity: value, child: child));
                },
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Verify Delivery OTP',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        enableInteractiveSelection: false,
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: '4 Digit OTP',
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF369D01), width: 1.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF369D01), width: 2),
                          ),
                          border: OutlineInputBorder(),
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 6),
                        onSubmitted: (_) => verifyNow(dialogContext, setDialogState),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: verifying ? null : () => verifyNow(dialogContext, setDialogState),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF369D01),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: verifying
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Verify', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmCashAndComplete(Map<String, dynamic> parcel) async {
    final amountRaw = parcel['price'] ?? parcel['total_price'] ?? parcel['totalPrice'];
    final amount = _asDouble(amountRaw);

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    final parcelId = _parcelId(parcel);
    if (parcelId.isEmpty) return;

    debugPrint('[confirm-cash] pressed parcelId=$parcelId');

    if (_confirmCashProcessingParcelIds.contains(parcelId)) {
      debugPrint('[confirm-cash] blocked duplicate call parcelId=$parcelId');
      return;
    }
    if (mounted) {
      setState(() {
        _confirmCashProcessingParcelIds.add(parcelId);
      });
    } else {
      _confirmCashProcessingParcelIds.add(parcelId);
    }

    bool successHandled = false;
    try {

      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) return;

      final rootContext = Navigator.of(context, rootNavigator: true).overlay!.context;
      showDialog(
        context: rootContext,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF00C853)),
        ),
      );

      final resp = await const ApiService().completeParcelRide(
        token: token,
        parcelId: parcelId,
      );

      debugPrint('[confirm-cash] response parcelId=$parcelId resp=${resp.toString()}');

      if (!mounted) return;

      // Close loader dialog
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      final ok = _isTrue(resp['success']) || _isTrue(resp['status']);
      if (!ok) {
        final rawMsg = (resp['message'] ?? 'Failed to complete ride').toString();
        final lower = rawMsg.toLowerCase();

        // Backend sometimes completes successfully but returns an error like "Unable to complete ride".
        // In that case, verify real status before showing any error.
        if (lower.contains('unable to complete ride')) {
          try {
            bool completedNow = false;
            for (int i = 0; i < 3; i++) {
              await Future.delayed(const Duration(milliseconds: 450));
              final polled = await const ApiService().getParcelStatus(parcelId: parcelId);
              final data = polled['data'];
              final m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
              final s = _text(m['status']).toLowerCase();
              if (s == 'completed' || s == 'complete') {
                completedNow = true;
                break;
              }
            }

            if (completedNow) {
              successHandled = true;
            } else {
              _showError('Failed to complete ride');
              return;
            }
          } catch (_) {
            _showError('Failed to complete ride');
            return;
          }
        } else {
          final msg = lower.contains('unable to complete ride') ? 'Failed to complete ride' : rawMsg;
          _showError(msg);
          return;
        }
      }
      successHandled = true;

      showDialog(
        context: rootContext,
        barrierDismissible: false,
        builder: (context) {
          Future.delayed(const Duration(seconds: 2), () {
            if (Navigator.canPop(context)) {
              Navigator.of(context, rootNavigator: true).pop();
            }
          });

          return Material(
            color: Colors.transparent,
            child: Dialog(
              backgroundColor: Colors.white,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet, color: Colors.green, size: 72),
                    const SizedBox(height: 16),
                    const Text(
                      "Payment Received",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "₹${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)} received successfully.",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Payment Method: Cash",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "Done",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      setState(() {
        parcel['status'] = 'COMPLETED';
        parcel['completedAt'] ??= DateTime.now().toIso8601String();
        _deliveryVerifiedParcelIds.remove(parcelId);

        _upcomingParcelsCache = _upcomingParcelsCache
            .where((e) => _parcelId(e) != parcelId)
            .toList(growable: false);

        final alreadyInCompleted = _completedParcelsCache.any((e) => _parcelId(e) == parcelId);
        if (!alreadyInCompleted) {
          _completedParcelsCache.insert(
            0,
            {
              ...parcel,
            },
          );
        }

        _completedParcelsCache.sort((a, b) => _completedAtOf(b).compareTo(_completedAtOf(a)));

        _parcelUpcomingFuture = Future.value(_upcomingParcelsCache);
        _parcelCompletedFuture = Future.value(_completedParcelsCache);
      });

      _tabController.animateTo(1);
    } catch (_) {
      if (!mounted) return;
      if (!successHandled) {
        _showError('Failed to complete ride');
      }
    } finally {
      if (!mounted) return;
      if (_confirmCashProcessingParcelIds.contains(parcelId)) {
        setState(() {
          _confirmCashProcessingParcelIds.remove(parcelId);
        });
      }
    }
  }

  Future<void> _callNumber(String phone) async {
    final p = phone.trim();
    if (p.isEmpty) return;

    final Uri uri = Uri(scheme: 'tel', path: p);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> openGoogleMap(String address) async {
    final a = address.trim();
    if (a.isEmpty) return;

    final Uri url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(a)}',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> handleNavigation(Map<String, dynamic> ride) async {
    final status = _text(ride['status']).toLowerCase();
    final pickup = _text(ride['pickup'] ?? ride['pickup_location'] ?? ride['pickupLocation']);
    final drop = _text(ride['drop'] ?? ride['drop_location'] ?? ride['dropLocation']);

    String targetAddress;
    if (status == 'accepted') {
      targetAddress = pickup;
    } else if (status == 'started' || status == 'ongoing' || status == 'in_progress') {
      targetAddress = drop;
    } else {
      targetAddress = pickup;
    }

    await openGoogleMap(targetAddress);
  }

  Future<void> _showParcelPickupOtpDialog(Map<String, dynamic> parcel) async {
    final parcelId = _text(parcel['_id'] ?? parcel['id']);
    if (parcelId.isEmpty) return;

    final controller = TextEditingController();
    bool verifying = false;
    bool dialogClosed = false;
    BuildContext? otpDialogContext;

    Future<void> verifyNow(BuildContext dialogContext, void Function(void Function()) setDialogState) async {
      if (verifying) return;
      final otp = controller.text.trim();
      if (otp.isEmpty) return;

      debugPrint("VERIFY BUTTON CLICK");
      print("STEP 1 OTP SUBMIT: Starting pickup OTP verification");

      debugPrint("ROUTE COUNT BEFORE VERIFY: ${Navigator.of(context, rootNavigator: true).widget}");

      try {
        if (!dialogClosed) {
          setDialogState(() => verifying = true);
        }
      } catch (_) {}

      try {
        print("STEP 2 API CALL START: Calling verifyParcelPickupOtp API");
        final token = (await const SessionService().getToken())?.trim() ?? '';
        if (token.isEmpty) {
          print("ERROR: Token is empty");
          return;
        }

        print("STEP 3 API CALL: Token validated, making API call");
        final resp = await const ApiService().verifyParcelPickupOtp(
          token: token,
          parcelId: parcelId,
          otp: otp,
        );

        print("STEP 3 API SUCCESS: API call completed");
        debugPrint("OTP API SUCCESS");

        if (!mounted) return;
        final ok = _isTrue(resp['success']) || _isTrue(resp['status']);
        if (ok) {
          print("STEP 4 VERIFY RESULT TRUE: Pickup OTP verification successful");

          try {
            HapticFeedback.lightImpact();
          } catch (_) {}

          // Close OTP dialog
          debugPrint("OTP VERIFY SUCCESS");
          dialogClosed = true;

          debugPrint("POP ATTEMPT 1: Using stored otpDialogContext");
          if (otpDialogContext != null && Navigator.of(otpDialogContext!).canPop()) {
            Navigator.of(otpDialogContext!).pop(true);
            debugPrint("OTP DIALOG POP SUCCESS: Using stored context");
          } else {
            debugPrint("POP ATTEMPT 1 FAILED: Context null or cannot pop");
          }

          debugPrint("POP ATTEMPT 2: Using dialogContext parameter");
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop(true);
            debugPrint("OTP DIALOG POP SUCCESS: Using dialogContext parameter");
          } else {
            debugPrint("POP ATTEMPT 2 FAILED: Cannot pop dialogContext");
          }

          // Wait before showing success dialog
          await Future.delayed(const Duration(milliseconds: 150));

          // Show success dialog
          debugPrint("SUCCESS DIALOG #1 OPEN");
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) {
              return Material(
                color: Colors.transparent,
                child: Dialog(
                  backgroundColor: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Color(0xFF369D01), size: 72),
                        SizedBox(height: 16),
                        Text(
                          'Parcel Ride Started',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18, color: Colors.black),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Proceed to delivery location',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w400, fontSize: 14, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );

          print("STEP 8 REFRESH STATE: Waiting before state refresh");
          await Future.delayed(const Duration(milliseconds: 1600));
          if (!mounted) return;
          print("STEP 8 CLOSE SUCCESS: Closing success dialog");
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          print("STEP 8 UPDATE STATE: Updating parcel state to STARTED");
          setState(() {
            parcel['status'] = 'STARTED';
            _upcomingParcelsCache = _upcomingParcelsCache
                .map((e) {
                  final id = _text(e['_id'] ?? e['id']);
                  if (id == parcelId) {
                    return {
                      ...e,
                      'status': 'STARTED',
                    };
                  }
                  return e;
                })
                .toList(growable: false);
            _parcelUpcomingFuture = Future.value(_upcomingParcelsCache);
          });
          print("STEP 8 NAVIGATION COMPLETE: Pickup OTP flow completed");
          return;
        }

        try {
          final polled = await const ApiService().getParcelStatus(parcelId: parcelId);
          final polledOk = _isTrue(polled['success']) || _isTrue(polled['status']);
          final data = polled['data'];
          final m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
          final status = _text(m['status']).toLowerCase();
          final startedNow = polledOk && (status == 'started' || status == 'in_progress');
          if (startedNow) {
            try {
              HapticFeedback.lightImpact();
            } catch (_) {}

            // Close OTP dialog before showing success dialog
            dialogClosed = true;
            debugPrint("OTP DIALOG POP SUCCESS: Polling fallback path");
            if (otpDialogContext != null && Navigator.of(otpDialogContext!).canPop()) {
              Navigator.of(otpDialogContext!).pop(true);
            } else if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop(true);
            }

            await Future.delayed(const Duration(milliseconds: 150));

            debugPrint("SUCCESS DIALOG #2 OPEN");
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) {
                return Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.92, end: 1.0),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: Opacity(opacity: value, child: child));
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFF369D01), size: 72),
                          SizedBox(height: 12),
                          Text(
                            'Parcel Ride Started 🚀',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Proceed to delivery location',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );

            await Future.delayed(const Duration(milliseconds: 1600));
            if (!mounted) return;
            Navigator.of(context).maybePop();
            setState(() {
              parcel['status'] = 'STARTED';
              _upcomingParcelsCache = _upcomingParcelsCache
                  .map((e) {
                    final id = _text(e['_id'] ?? e['id']);
                    if (id == parcelId) {
                      return {
                        ...e,
                        'status': 'STARTED',
                      };
                    }
                    return e;
                  })
                  .toList(growable: false);
              _parcelUpcomingFuture = Future.value(_upcomingParcelsCache);
            });
            return;
          }
        } catch (_) {}

        final rawMsg = (resp['message'] ?? 'Invalid OTP').toString();
        final lower = rawMsg.toLowerCase();
        final msg = lower.contains('unable to start parcel') || lower.contains('unable to process') || lower.contains('request not found')
            ? 'Invalid OTP'
            : rawMsg;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP verification failed')));
      } finally {
        try {
          if (!dialogClosed) {
            setDialogState(() => verifying = false);
          }
        } catch (_) {}
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        otpDialogContext = dialogContext;
        debugPrint("OTP DIALOG OPEN");
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.92, end: 1.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: Opacity(opacity: value, child: child));
                },
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Enter Pickup OTP',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        enableInteractiveSelection: false,
                        decoration: const InputDecoration(
                          counterText: '',
                          hintText: '4 Digit OTP',
                          border: OutlineInputBorder(),
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 6),
                        onSubmitted: (_) => verifyNow(dialogContext, setDialogState),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: verifying ? null : () => verifyNow(dialogContext, setDialogState),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF369D01),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: verifying
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Verify', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (ok == true) {
      setState(() {
        _parcelUpcomingFuture = Future.value(_upcomingParcelsCache);
        _parcelCompletedFuture = Future.value(_completedParcelsCache);
      });
    }
  }


  Future<List<Map<String, dynamic>>> _fetchUpcomingParcels() async {
    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) return <Map<String, dynamic>>[];
      final resp = await const ApiService().getUpcomingParcels(token: token);
      final ok = resp['success'] == true;
      final data = ok && resp['data'] is List ? (resp['data'] as List) : const <dynamic>[];
      final list = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      _upcomingParcelsCache = list;
      for (final parcel in list) {
        print("PARCEL STATUS FROM API: ${parcel['status']}");
        print("PARCEL DRIVER STATUS: ${parcel['driver_status']}");
        print("PARCEL USER STATUS: ${parcel['user_status']}");
      }
      return list;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCompletedParcels() async {
    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) return <Map<String, dynamic>>[];
      final resp = await const ApiService().getCompletedParcels(token: token);
      final ok = resp['success'] == true;
      final data = ok && resp['data'] is List ? (resp['data'] as List) : const <dynamic>[];
      final list = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      list.sort((a, b) => _completedAtOf(b).compareTo(_completedAtOf(a)));
      _completedParcelsCache = list;
      return list;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCancelledParcels() async {
    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) return <Map<String, dynamic>>[];
      final resp = await const ApiService().getCancelledParcels(token: token);
      final ok = resp['success'] == true;
      final data = ok && resp['data'] is List ? (resp['data'] as List) : const <dynamic>[];
      final list = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

      final local = _parcelActivityState?.cancelledParcels ?? const <Map<String, dynamic>>[];
      final Map<String, Map<String, dynamic>> byId = <String, Map<String, dynamic>>{
        for (final e in list) _text(e['_id'] ?? e['id']): e,
      };
      for (final p in local) {
        final id = _text(p['_id'] ?? p['id']);
        if (id.isEmpty) continue;
        byId.putIfAbsent(id, () => Map<String, dynamic>.from(p));
      }

      final merged = byId.values.toList(growable: false);
      _cancelledParcelsCache = merged;
      return merged;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  void refreshRideList() {
    if (!mounted) return;
    setState(() {
      _ridesFuture = _fetchAllRides();
      _parcelUpcomingFuture = _fetchUpcomingParcels();
      _parcelCompletedFuture = _fetchCompletedParcels();
      _parcelCancelledFuture = _fetchCancelledParcels();
    });
  }

  void _showError(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _completeParcelRide(Map<String, dynamic> parcel) async {
    final parcelId = _text(parcel['_id'] ?? parcel['id']);
    if (parcelId.isEmpty) {
      _showError('Missing parcel id');
      return;
    }
    setState(() {
      parcel['status'] = 'COMPLETED';
      parcel['completedAt'] ??= DateTime.now().toIso8601String();
      _deliveryVerifiedParcelIds.remove(parcelId);
      _upcomingParcelsCache = _upcomingParcelsCache
          .where((e) => _text(e['_id'] ?? e['id']) != parcelId)
          .toList(growable: false);
      final alreadyInCompleted = _completedParcelsCache.any((e) => _text(e['_id'] ?? e['id']) == parcelId);
      if (!alreadyInCompleted) {
        _completedParcelsCache.insert(
          0,
          {
            ...parcel,
          },
        );
      }
      _completedParcelsCache.sort((a, b) => _completedAtOf(b).compareTo(_completedAtOf(a)));
      _parcelUpcomingFuture = Future.value(_upcomingParcelsCache);
      _parcelCompletedFuture = Future.value(_completedParcelsCache);
    });
    _tabController.animateTo(1);
  }

  void _showCompleteSuccess() {
    print('DEBUG: _showCompleteSuccess called - REMOVED SUCCESS DIALOG TO FIX DOUBLE LOADER');
    // REMOVED: Success dialog that was causing second loader/blocking UI
    // The first loader in _completeRide is sufficient feedback
    
    print('DEBUG: Animating to tab 1');
    _tabController.animateTo(1);
    print('DEBUG: Calling refreshRideList');
    refreshRideList();
    print('DEBUG: refreshRideList completed');
  }

  Future<void> _completeRide(Map<String, dynamic> ride) async {
    print('DEBUG: _completeRide called for rideId=${ride['_id'] ?? ride['id']}');
    final rideId = _text(ride['_id'] ?? ride['id']);
    if (rideId.isEmpty) {
      _showError('Missing ride id');
      return;
    }

    print('DEBUG: Showing loading dialog');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00C853)),
      ),
    );

    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) {
        print('DEBUG: Token empty, popping loader');
        Navigator.of(context).maybePop();
        _showError('Unauthorized');
        return;
      }

      print('DEBUG: Calling completeIntercityRide API');
      final response = await const ApiService().completeIntercityRide(
        token: token,
        rideId: rideId,
      );

      try {
        debugPrint('INTERCITY COMPLETE API RESP: $response');
      } catch (_) {}

      if (!mounted) return;
      print('DEBUG: API call complete, popping loader');
      Navigator.of(context).maybePop();

      final data = response['data'];
      final apiStatusRaw = (data is Map ? data['status'] : null) ?? response['status'];
      final apiStatus = (apiStatusRaw ?? '').toString().trim().toLowerCase();
      final ok = response['success'] == true || apiStatus == 'completed';
      print('DEBUG: API success=$ok, status=$apiStatus');
      if (!ok) {
        _showError((response['message'] ?? 'Failed to complete ride').toString());
        return;
      }

      print('DEBUG: Calling _showCompleteSuccess');
      _showCompleteSuccess();
    } catch (_) {
      print('DEBUG: Exception in _completeRide, popping loader');
      if (!mounted) return;
      Navigator.of(context).maybePop();
      _showError('Something went wrong');
    }
  }

  Future<void> _confirmCashPayment(Map<String, dynamic> ride) async {
    print('DEBUG: _confirmCashPayment called for rideId=${ride['_id'] ?? ride['id']}');
    final rideId = _text(ride['_id'] ?? ride['id']);
    if (rideId.isEmpty) {
      _showError('Missing ride id');
      return;
    }

    // Determine ride type
    final rideType = (ride['ride_type'] ?? ride['rideType'] ?? 'normal').toString().trim();
    print('DEBUG: RIDE TYPE: $rideType');
    print('DEBUG: RIDE ID: $rideId');

    final shownPrice = _asDouble(
      ride['price'] ??
          ride['amount'] ??
          ride['paid_amount'] ??
          ride['total_price'] ??
          ride['ride_price'] ??
          ride['fare'],
    );

    try {
      print('DEBUG: Showing loading dialog');
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF00C853)),
        ),
      );

      print('DEBUG: Calling confirmCashReceived API');
      final res = await const ApiService().confirmCashReceived(rideId: rideId, token: (await const SessionService().getToken() ?? '').trim(), rideType: rideType);
      print('DEBUG: confirmCashReceived response=$res');
      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;
      print('DEBUG: Popping loading dialog');
      Navigator.of(context).maybePop();

      final ok = res['success'] == true;
      print('DEBUG: API success=$ok');
      if (!ok) {
        _showError((res['message'] ?? 'Failed to confirm payment').toString());
        return;
      }

      print('DEBUG: Showing success dialog');
      showDialog<void>(
        context: context,
        builder: (context) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF00C853),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'Payment Received',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '₹${shownPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00C853),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Cash payment confirmed successfully',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C853),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      print('DEBUG: Starting 1 second delay before popping success dialog');
      Future.delayed(const Duration(seconds: 1), () {
        print('DEBUG: Delay complete, popping success dialog');
        if (!mounted) return;
        Navigator.of(context).maybePop();
        print('DEBUG: Calling refreshRideList');
        refreshRideList();
        print('DEBUG: refreshRideList completed');
      });

      // Update UI to remove RECEIVED button and show Completed status
      setState(() {
        // Update ride status to completed
        ride['status'] = 'completed';
        ride['payment_status'] = 'completed';

        // Update cache to reflect changes
        _completedParcelsCache = _completedParcelsCache
            .map((e) {
              final id = _text(e['_id'] ?? e['id']);
              if (id == rideId) {
                return {
                  ...e,
                  'status': 'completed',
                  'payment_status': 'completed',
                };
              }
              return e;
            })
            .toList(growable: false);
        _parcelCompletedFuture = Future.value(_completedParcelsCache);
      });
    } catch (_) {
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      _showError('Failed to confirm payment');
    }
  }

  void _openReviewScreen(Map<String, dynamic> ride, double paidAmount, String riderName, String userImage) {
    final userId = _text(
      ride['user_id'] ??
          ride['rider_id'] ??
          (ride['user'] is Map ? (ride['user'] as Map)['_id'] ?? (ride['user'] as Map)['id'] : null),
    );

    debugPrint('USER ID: $userId');

    final isParcel = _text(ride['sender_name']).isNotEmpty || _text(ride['receiver_name']).isNotEmpty;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverGiveReviewScreen(
          rideId: _text(ride['_id'] ?? ride['id']),
          userId: userId,
          userName: riderName,
          userImageUrl: userImage,
          paidAmount: paidAmount,
          reviewType: isParcel ? 'parcel' : 'driver_to_user',
        ),
      ),
    );
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '';
    final raw = v.toString().trim();
    if (raw.isEmpty) return '';
    final d = DateTime.tryParse(raw);
    final dt = (d ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal();
    if (d == null) return raw;

    String two(int n) => n.toString().padLeft(2, '0');
    final hour = dt.hour;
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final ampm = hour >= 12 ? 'PM' : 'AM';
    return '${two(dt.day)}-${two(dt.month)}-${dt.year} ${two(h12)}:${two(dt.minute)} $ampm';
  }

  @override
  void initState() {
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialIndex.clamp(0, 2));
    super.initState();
    _loadDriverId();
    _ridesFuture = _fetchAllRides();
    _parcelUpcomingFuture = _fetchUpcomingParcels();
    _parcelCompletedFuture = _fetchCompletedParcels();
    _parcelCancelledFuture = _fetchCancelledParcels();

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && _tabController.index == 2) {
        setState(() {
          _parcelCancelledFuture = _fetchCancelledParcels();
        });
      }
    });

    _startExpiryCheckPolling();
  }

  Future<void> _loadDriverId() async {
    final id = (await const SessionService().getDriverId())?.trim() ?? '';
    if (!mounted) return;
    if (_driverId == id) return;
    setState(() {
      _driverId = id;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Provider.of<ParcelActivityState>(context);
    if (!identical(_parcelActivityState, next)) {
      _parcelActivityState?.removeListener(_onParcelActivityChanged);
      _parcelActivityState = next;
      _parcelActivityState?.addListener(_onParcelActivityChanged);
      _onParcelActivityChanged();
    }
  }

  void _onParcelActivityChanged() {
    if (!mounted) return;
    final state = _parcelActivityState;
    if (state == null) return;

    final incoming = state.cancelledParcels;
    if (incoming.isEmpty) return;

    bool changed = false;
    final Map<String, Map<String, dynamic>> byId = <String, Map<String, dynamic>>{
      for (final e in _cancelledParcelsCache)
        _text(e['_id'] ?? e['id']): e,
    };

    for (final p in incoming) {
      final id = _text(p['_id'] ?? p['id']);
      if (id.isEmpty) continue;
      final existing = byId[id];
      if (existing == null) {
        byId[id] = Map<String, dynamic>.from(p);
        changed = true;
      }
    }

    if (!changed) return;

    setState(() {
      _cancelledParcelsCache = byId.values.toList(growable: false);
      _parcelCancelledFuture = Future.value(_cancelledParcelsCache);
    });
  }

  @override
  void dispose() {
    _expiryCheckTimer?.cancel();
    _parcelActivityState?.removeListener(_onParcelActivityChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchAllRides() async {
    final token = (await const SessionService().getToken())?.trim() ?? '';
    if (token.isEmpty) return <Map<String, dynamic>>[];

    Future<List<Map<String, dynamic>>> parseResponse(Response resp) async {
      dynamic decoded = resp.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) return <Map<String, dynamic>>[];

      final ok = decoded['status'] == true || decoded['success'] == true;
      final data = decoded['data'] ?? decoded['rides'];
      if (!ok || data is! List) return <Map<String, dynamic>>[];

      final out = <Map<String, dynamic>>[];
      for (final item in data) {
        if (item is Map) out.add(Map<String, dynamic>.from(item));
      }
      return out;
    }

    final uri = Uri.parse('$baseUrl/driver/activity-rides');
    final resp = await DioClient.dio.get(
      uri.toString(),
      options: Options(
        validateStatus: (_) => true,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ),
    );

    return parseResponse(resp);
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  IconData _vehicleIcon(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'bike') return Icons.two_wheeler;
    if (v == 'suv') return Icons.directions_car_filled;
    if (v == 'car') return Icons.directions_car;
    return Icons.local_taxi;
  }

  String _vehicleLabel(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'bike') return 'Bike';
    if (v == 'car') return 'Car';
    if (v == 'suv') return 'SUV';
    return 'Vehicle';
  }

  Color _badgeBg(String status) {
    switch (status) {
      case 'upcoming':
        return const Color(0xFFEFF6FF);
      case 'accepted':
        return const Color(0xFFF0FDF4);
      case 'arrived':
        return const Color(0xFFFFFBEB);
      case 'completed':
        return const Color(0xFFF1F5F9);
      default:
        return const Color(0xFFF0FDF4);
    }
  }

  Color _badgeFg(String status) {
    switch (status) {
      case 'upcoming':
        return const Color(0xFF2563EB);
      case 'accepted':
        return const Color(0xFF16A34A);
      case 'arrived':
        return const Color(0xFFD97706);
      case 'completed':
        return const Color(0xFF0F172A);
      default:
        return const Color(0xFF16A34A);
    }
  }

  Widget buildRideList(String status) {
    if (status != 'upcoming') {
      if (status == 'completed') {
        return FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: Future.wait<List<Map<String, dynamic>>>([
            _ridesFuture ?? Future.value(<Map<String, dynamic>>[]),
            _parcelCompletedFuture ?? Future.value(<Map<String, dynamic>>[]),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final combined = snapshot.data;
            final ridesAll = (combined != null && combined.isNotEmpty) ? combined[0] : <Map<String, dynamic>>[];
            final parcelsAll = (combined != null && combined.length > 1) ? combined[1] : <Map<String, dynamic>>[];

            final rides = ridesAll.where((ride) {
              final s = _text(ride['status']).toLowerCase();
              return s == 'completed';
            }).toList();

            final parcels = parcelsAll.where((p) {
              final s = _text(p['status']).toLowerCase();
              return s == 'completed';
            }).toList();

            final all = <Map<String, dynamic>>[
              ...parcels.map((e) => {...e, 'ride_type': 'parcel'}),
              ...rides,
            ];

            all.sort((a, b) => _completedAtOf(b).compareTo(_completedAtOf(a)));

            if (all.isEmpty) {
              return const Center(
                child: Text(
                  'No completed rides',
                  style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
                ),
              );
            }

            return ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: all.length,
              itemBuilder: (context, index) {
                final item = all[index];
                final rideType = _text(item['rideType'] ?? item['ride_type']).toLowerCase();
                if (rideType == 'parcel') {
                  return _parcelUpcomingCard(item, index);
                }
                final t = _text(item['rideType'] ?? item['ride_type']).toLowerCase();
                if (t == 'intercity') {
                  return _rideCard(item, status, index);
                }
                return _normalRideCard(item, index);
              },
            );
          },
        );
      }

      if (status == 'canceled') {
        return FutureBuilder<List<List<Map<String, dynamic>>>>(
          future: Future.wait<List<Map<String, dynamic>>>([
            _ridesFuture ?? Future.value(<Map<String, dynamic>>[]),
            _parcelCancelledFuture ?? Future.value(<Map<String, dynamic>>[]),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final combined = snapshot.data;
            final ridesAll = (combined != null && combined.isNotEmpty) ? combined[0] : <Map<String, dynamic>>[];
            final parcelsAll = (combined != null && combined.length > 1) ? combined[1] : <Map<String, dynamic>>[];

            final rides = ridesAll.where((ride) {
              final s = _text(ride['status']).toLowerCase();
              return s == 'cancelled' || s == 'canceled' || s == 'expired';
            }).toList();

            final parcels = parcelsAll.where((p) {
              final s = _text(p['status']).toLowerCase();
              return s == 'cancelled' ||
                  s == 'canceled' ||
                  s == 'rejected' ||
                  s == 'driver_cancelled' ||
                  s == 'driver_canceled' ||
                  s == 'driver_rejected' ||
                  s == 'expired';
            }).toList();

            final all = <Map<String, dynamic>>[
              ...parcels.map((e) => {...e, 'ride_type': 'parcel'}),
              ...rides,
            ];

            if (all.isEmpty) {
              return const Center(
                child: Text(
                  'No canceled rides',
                  style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
                ),
              );
            }

            return ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: all.length,
              itemBuilder: (context, index) {
                final item = all[index];
                final rideType = _text(item['rideType'] ?? item['ride_type']).toLowerCase();
                if (rideType == 'parcel') {
                  return _parcelUpcomingCard(item, index);
                }
                final t = _text(item['rideType'] ?? item['ride_type']).toLowerCase();
                if (t == 'intercity') {
                  return _rideCard(item, status, index);
                }
                return _normalRideCard(item, index);
              },
            );
          },
        );
      }

      return FutureBuilder<List<Map<String, dynamic>>>(
        future: _ridesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final ridesAll = snapshot.data ?? <Map<String, dynamic>>[];
          final rides = ridesAll.where((ride) {
            final s = _text(ride['status']).toLowerCase();
            if (status == 'completed') return s == 'completed';
            if (status == 'canceled') return s == 'cancelled';
            return true;
          }).toList();
          if (rides.isEmpty) {
            return Center(
              child: Text(
                'No $status rides',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
              ),
            );
          }

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(12),
            itemCount: rides.length,
            itemBuilder: (context, index) {
              final ride = rides[index];
              final rideType = _text(ride['rideType'] ?? ride['ride_type']).toLowerCase();
              if (rideType == 'intercity') {
                return _rideCard(ride, status, index);
              }
              return _normalRideCard(ride, index);
            },
          );
        },
      );
    }

    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait<List<Map<String, dynamic>>>([
        _ridesFuture ?? Future.value(<Map<String, dynamic>>[]),
        _parcelUpcomingFuture ?? Future.value(<Map<String, dynamic>>[]),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final combined = snapshot.data;
        final ridesAll = (combined != null && combined.isNotEmpty) ? combined[0] : <Map<String, dynamic>>[];
        final parcelsAll = (combined != null && combined.length > 1) ? combined[1] : <Map<String, dynamic>>[];

        final currentDriverId = _driverId.trim();
        final rideItems = ridesAll.where((ride) {
          final s = _text(ride['status']).toLowerCase();
          final rideType = _text(ride['rideType'] ?? ride['ride_type']).toLowerCase();
          if (rideType == 'intercity') {
            final assignedDriverId = _text(ride['assigned_driver_id'] ?? ride['assignedDriverId']);
            final selectedDriverId = _text(ride['selected_driver_id'] ?? ride['selectedDriverId']);
            final acceptedDriverId = _text(ride['accepted_driver_id'] ?? ride['acceptedDriverId']);
            if (assignedDriverId.isNotEmpty && assignedDriverId != currentDriverId) return false;
            if (selectedDriverId.isNotEmpty && selectedDriverId != currentDriverId) return false;
            if (acceptedDriverId.isNotEmpty && acceptedDriverId != currentDriverId) return false;
            if ((s == 'assigned' || s == 'accepted' || s == 'arrived' || s == 'ongoing' || s == 'started') &&
                assignedDriverId.isEmpty &&
                selectedDriverId.isEmpty &&
                acceptedDriverId.isEmpty) {
              return false;
            }
          }
          return s == 'pending' || s == 'assigned' || s == 'accepted' || s == 'arrived' || s == 'ongoing' || s == 'started';
        }).toList();

        final cancelledLocalIds = <String>{
          for (final e in _cancelledParcelsCache) _parcelId(e),
          for (final e in (_parcelActivityState?.cancelledParcels ?? const <Map<String, dynamic>>[])) _parcelId(e),
        };

        final parcelItems = parcelsAll.where((p) {
          final s = _text(p['status']).toLowerCase();
          final id = _parcelId(p);
          if (id.isNotEmpty && cancelledLocalIds.contains(id)) return false;
          return s == 'accepted' || s == 'in_progress' || s == 'started';
        }).toList();

        final all = <Map<String, dynamic>>[
          ...parcelItems.map((e) => {...e, 'ride_type': 'parcel'}),
          ...rideItems,
        ];

        if (all.isEmpty) {
          return const Center(
            child: Text(
              'No upcoming rides',
              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
            ),
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: all.length,
          itemBuilder: (context, index) {
            final item = all[index];
            final rideType = _text(item['rideType'] ?? item['ride_type']).toLowerCase();
            if (rideType == 'parcel') {
              return _parcelUpcomingCard(item, index);
            }
            if (rideType == 'intercity') {
              return _rideCard(item, status, index);
            }
            return _normalRideCard(item, index);
          },
        );
      },
    );
  }

  Widget _parcelUpcomingCard(Map<String, dynamic> parcel, int index) {
    final pickup = _text(parcel['pickup'] ?? parcel['pickup_location'] ?? parcel['pickupLocation']);
    final drop = _text(parcel['drop'] ?? parcel['drop_location'] ?? parcel['dropLocation']);
    final priceRaw = parcel['price'] ?? parcel['total_price'] ?? parcel['totalPrice'];
    final price = _asDouble(priceRaw);
    
    final pickupDate = _text(parcel['pickup_date'] ?? parcel['pickupDate']);
    final pickupTime = _text(parcel['pickup_time'] ?? parcel['pickupTime']);
    
    String date;
    if (pickupDate.isNotEmpty && pickupTime.isNotEmpty) {
      date = '$pickupDate • $pickupTime';
    } else {
      date = _fmtDate(parcel['pickup_time'] ?? parcel['pickupTime'] ?? parcel['created_at'] ?? parcel['createdAt']);
    }

    final description = _text(parcel['description'] ?? parcel['desc'] ?? parcel['title']);
    final status = _text(parcel['status']).toLowerCase();
    final isCancelled = status == 'cancelled' ||
        status == 'canceled' ||
        status == 'rejected' ||
        status == 'driver_cancelled' ||
        status == 'driver_canceled' ||
        status == 'driver_rejected';
    final isExpired = status == 'expired';
    final isCompleted = status == 'completed' || status == 'delivered';
    final isStarted = status == 'started' || status == 'ongoing' || status == 'in_progress';
    final deliveryVerified = _deliveryVerifiedParcelIds.contains(_parcelId(parcel));
    final showNavigate = !isCancelled && !isExpired && (status == 'accepted' || status == 'started');

    IconData parcelIcon;
    if (!isStarted || description.isEmpty) {
      parcelIcon = Icons.local_shipping;
    } else {
      final d = description.toLowerCase();
      if (d.contains('book')) {
        parcelIcon = Icons.menu_book;
      } else if (d.contains('box') || d.contains('parcel')) {
        parcelIcon = Icons.inventory;
      } else {
        parcelIcon = Icons.local_shipping;
      }
    }

    final userPhone = _text(
      parcel['user_phone'] ??
          parcel['sender_phone'] ??
          parcel['customer_phone'] ??
          parcel['phone'],
    );
    final receiverId = _text(
      parcel['user_id'] ??
          parcel['userId'] ??
          parcel['customer_id'] ??
          parcel['customerId'] ??
          (parcel['user'] is Map ? (parcel['user'] as Map)['_id'] : null) ??
          (parcel['user'] is Map ? (parcel['user'] as Map)['id'] : null),
    );
    final receiverName = _text(
      parcel['user_name'] ??
          parcel['userName'] ??
          parcel['sender_name'] ??
          parcel['customer_name'] ??
          parcel['customerName'] ??
          (parcel['user'] is Map ? (parcel['user'] as Map)['name'] : null) ??
          (parcel['user'] is Map ? (parcel['user'] as Map)['fullName'] : null),
    );

    final receiverImage = _text(
      parcel['user_image'] ??
          parcel['sender_image'] ??
          (parcel['user'] is Map ? (parcel['user'] as Map)['image'] : null) ??
          (parcel['user'] is Map ? (parcel['user'] as Map)['user_image'] : null),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + (index.clamp(0, 6) * 40)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: (!isCancelled && !isExpired && isStarted)
            ? () async {
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => ParcelDropMapScreen(parcel: parcel)),
                );
                if (ok == true) {
                  if (!mounted) return;
                  _tabController.animateTo(1);
                }
              }
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 4)),
            ],
            border: Border.all(color: const Color(0xFFE6E6E6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(parcelIcon, color: const Color(0xFF369D01)),
                      const SizedBox(width: 8),
                      Text(
                        isStarted && description.isNotEmpty ? description : 'Parcel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isExpired
                          ? const Color(0xFFFF9800)
                          : isCancelled
                          ? const Color(0xFFF1F5F9)
                          : isCompleted
                          ? const Color(0xFFF1F5F9)
                          : (isStarted ? const Color(0xFFE0F2FE) : const Color(0xFFF0FDF4)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isExpired ? 'EXPIRED' : (isCancelled ? 'CANCELLED' : (isCompleted ? 'COMPLETED' : (isStarted ? 'STARTED' : 'ACCEPTED'))),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: isExpired
                            ? Colors.white
                            : isCancelled
                            ? const Color(0xFF0F172A)
                            : isCompleted
                            ? const Color(0xFF0F172A)
                            : (isStarted ? const Color(0xFF2563EB) : const Color(0xFF16A34A)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.green),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pickup.isEmpty ? '-' : pickup,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      drop.isEmpty ? '-' : drop,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Pickup: $date', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '₹${price.toStringAsFixed(price % 1 == 0 ? 0 : 2)}',
                    style: const TextStyle(color: Color(0xFF369D01), fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 12),
              if (!isCancelled && !isExpired && !isCompleted) ...[
                Row(
                  children: [
                    SizedBox(
                      height: 46,
                      width: 54,
                      child: ElevatedButton(
                        onPressed: userPhone.isEmpty ? null : () => _callNumber(userPhone),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF369D01),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Icon(Icons.call),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 46,
                      width: 54,
                      child: ElevatedButton(
                        onPressed: () async {
                          final rideId = _parcelId(parcel);
                          if (rideId.isEmpty) return;
                          final senderId = (await const SessionService().getDriverId())?.trim() ?? '';
                          if (senderId.isEmpty) return;

                          if (receiverId.isEmpty) return;
                          if (!context.mounted) return;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RideChatScreen(
                                rideId: rideId,
                                senderId: senderId,
                                receiverId: receiverId,
                                senderRole: 'driver',
                                title: receiverName.isEmpty ? 'Chat' : receiverName,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF369D01),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Icon(Icons.chat_bubble_outline),
                      ),
                    ),
                    if (showNavigate) ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 46,
                        width: 54,
                        child: ElevatedButton(
                          onPressed: () => handleNavigation(parcel),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Icon(Icons.navigation),
                        ),
                      ),
                    ],
                    if (!isStarted) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed: () => _showParcelPickupOtpDialog(parcel),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF369D01),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text(
                              'PICKUP',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ] else if (isCompleted) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Payment Completed',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_isTrue(parcel['is_reviewed']))
                  const Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Reviewed ✔',
                      style: TextStyle(
                        color: Color(0xFF369D01),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () async {
                      final rideId = _parcelId(parcel);
                      if (rideId.isEmpty) return;

                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DriverGiveReviewScreen(
                            rideId: _text(parcel['_id'] ?? parcel['id']),
                            userId: _text(
                              parcel['user_id'] ??
                                  parcel['rider_id'] ??
                                  (parcel['user'] is Map ? (parcel['user'] as Map)['_id'] ?? (parcel['user'] as Map)['id'] : null),
                            ),
                            userName: '',
                            userImageUrl: '',
                            paidAmount: price,
                            reviewType: 'parcel',
                          ),
                        ),
                      );

                      if (ok == true) {
                        if (!mounted) return;
                        setState(() {
                          final id = _parcelId(parcel);
                          _completedParcelsCache = _completedParcelsCache.map((e) {
                            final pid = _parcelId(e);
                            if (pid == id) {
                              return {
                                ...e,
                                'is_reviewed': true,
                              };
                            }
                            return e;
                          }).toList(growable: false);
                          _parcelCompletedFuture = Future.value(_completedParcelsCache);
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF369D01)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Review',
                        style: TextStyle(
                          color: Color(0xFF369D01),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
              if (!isCancelled && isStarted && !isCompleted) ...[
                const SizedBox(height: 12),
                if (!deliveryVerified)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: SlideAction(
                      sliderButtonIcon: const Icon(Icons.arrow_forward, color: Colors.white),
                      outerColor: const Color(0xFF369D01),
                      innerColor: const Color(0xFF2B7A01),
                      text: 'Swipe to Deliver',
                      textStyle: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                      onSubmit: () async {
                        if (isCompleted) return;
                        await _showDeliveryOtpDialog(parcel);
                      },
                    ),
                  )
                else
                  Builder(
                    builder: (context) {
                      final pid = _parcelId(parcel);
                      final processing = pid.isNotEmpty && _confirmCashProcessingParcelIds.contains(pid);
                      final paymentType = _text(parcel['payment_type'] ?? parcel['paymentType'] ?? parcel['payment_method'] ?? parcel['paymentMethod'] ?? 'COD').toLowerCase();
                      final isWallet = paymentType == 'wallet';
                      final waitingPayment = pid.isNotEmpty && _parcelWaitingPaymentIds.contains(pid) && isWallet;

                      if (waitingPayment) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF369D01).withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF369D01).withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF369D01)),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Waiting for customer payment...',
                                  style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2B7A01)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Thanks for rating!')),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF369D01),
                                side: const BorderSide(color: Color(0xFF369D01)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              icon: const Icon(Icons.star),
                              label: const Text('Rate Customer', style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: processing ? null : () => _confirmCashAndComplete(parcel),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF369D01),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              icon: const Icon(Icons.payments),
                              label: const Text('Payment Received', style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _normalRideCard(Map<String, dynamic> ride, int index) {
    final name = _text(
      ride['userName'] ??
          ride['user_name'] ??
          ride['customerName'] ??
          ride['customer_name'] ??
          (ride['user'] is Map ? (ride['user'] as Map)['name'] : null),
    );
    final userImage = _text(
      ride['userImage'] ??
          ride['user_image'] ??
          ride['image'] ??
          (ride['user'] is Map ? (ride['user'] as Map)['profileImage'] : null),
    );
    final date = _fmtDate(ride['createdAt'] ?? ride['created_at'] ?? ride['created_at'] ?? ride['createdAt']);

    final pickupRaw = ride['pickup'];
    final dropRaw = ride['drop'];
    final pickup = _text((pickupRaw is Map ? pickupRaw['address'] : null) ?? pickupRaw);
    final drop = _text((dropRaw is Map ? dropRaw['address'] : null) ?? dropRaw);

    final vehicleRaw = _text(ride['vehicle_type'] ?? ride['vehicleType']);
    final distanceRaw = ride['distance'];
    final durationRaw = ride['duration'];

    String distanceText;
    if (distanceRaw is num) {
      distanceText = '${distanceRaw.toString()} km';
    } else {
      final s = _text(distanceRaw);
      distanceText = s.isEmpty ? '0 km' : s;
    }

    String durationText;
    if (durationRaw is num) {
      durationText = '${durationRaw.toString()} mins';
    } else {
      final s = _text(durationRaw);
      durationText = s.isEmpty ? '0 mins' : s;
    }

    final amount = _asDouble(ride['fare'] ?? ride['finalFare'] ?? ride['final_fare'] ?? ride['finalFare']);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + (index.clamp(0, 6) * 40)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: userImage.isNotEmpty ? NetworkImage(userImage) : null,
                    child: userImage.isNotEmpty
                        ? null
                        : Text(
                            (name.isEmpty ? 'C' : name.substring(0, 1)).toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name.isEmpty ? 'Customer' : name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.calendar_month, size: 18, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(date, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: Color(0xFF00A651), shape: BoxShape.circle),
                      ),
                      Container(width: 2, height: 28, color: Colors.grey.shade300),
                      const Icon(Icons.location_on, size: 18, color: Colors.red),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pickup,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          drop,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Icon(_vehicleIcon(vehicleRaw), size: 18, color: const Color(0xFF00A651)),
                  const SizedBox(width: 6),
                  Text(_vehicleLabel(vehicleRaw), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 14),
                  const Icon(Icons.route, size: 18, color: Colors.black87),
                  const SizedBox(width: 6),
                  Text(distanceText, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 14),
                  const Icon(Icons.timer, size: 18, color: Colors.black87),
                  const SizedBox(width: 6),
                  Text(durationText, style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF0FFF7),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_balance_wallet, size: 18, color: Color(0xFF00A651)),
                  const SizedBox(width: 8),
                  Text(
                    '₹${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)}',
                    style: const TextStyle(color: Color(0xFF00A651), fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rideCard(Map<String, dynamic> ride, String status, int index) {
    final riderName = _text(
      ride['userName'] ??
          ride['rider_name'] ??
          ride['customer_name'] ??
          ride['name'] ??
          (ride['user'] is Map ? (ride['user'] as Map)['name'] : null),
    );
    final userImage = _text(
      ride['userImage'] ??
          ride['user_image'] ??
          ride['rider_image'] ??
          ride['image'] ??
          (ride['user'] is Map ? (ride['user'] as Map)['profile_image'] : null),
    );

    final acceptedFare = _asDouble(ride['accepted_fare'] ?? ride['acceptedFare']);
    final finalPrice = _asDouble(ride['final_price'] ?? ride['finalPrice']);
    final totalPrice = _asDouble(ride['total_price'] ?? ride['totalPrice'] ?? ride['price'] ?? ride['amount']);
    final shownPrice = acceptedFare > 0 ? acceptedFare : (finalPrice > 0 ? finalPrice : totalPrice);

    final km = _asDouble(ride['total_km'] ?? ride['totalKm'] ?? ride['km']);
    final rating = _asDouble(
      (ride['user'] is Map ? (ride['user'] as Map)['rating'] : null) ?? ride['rating'] ?? ride['user_rating'],
    );
    final personsRaw = ride['persons'] ?? ride['passengers'] ?? 1;
    final persons = int.tryParse(personsRaw.toString()) ?? 1;

    final pickup = _text(ride['pickup'] ?? ride['pickup_location']);
    final drop = _text(ride['drop'] ?? ride['drop_location'] ?? ride['destination']);

    IntercityRequestModel? intercity;
    try {
      intercity = IntercityRequestModel.fromJson(ride);
    } catch (_) {
      intercity = null;
    }

    print('========== RIDE CARD DATA ==========');
    print('RIDE DATA => $ride');
    print('RIDE pickup_date => ${ride['pickup_date']}');
    print('RIDE pickup_time => ${ride['pickup_time']}');
    print('RIDE pickupDate => ${ride['pickupDate']}');
    print('RIDE pickupTime => ${ride['pickupTime']}');
    print('RIDE arrival_time => ${ride['arrival_time']}');
    print('RIDE arrivalTime => ${ride['arrivalTime']}');
    print('INTERCITY MODEL => $intercity');
    if (intercity != null) {
      print('INTERCITY pickupDate => ${intercity!.pickupDate}');
      print('INTERCITY pickupTime => ${intercity!.pickupTime}');
      print('INTERCITY arrivalTime => ${intercity!.arrivalTime}');
    }
    print('=====================================');

    final pickupDate = _text(ride['pickup_date'] ?? ride['pickupDate'] ?? (intercity?.pickupDate ?? ''));
    final pickupTime = _text(ride['pickup_time'] ?? ride['pickupTime'] ?? (intercity?.pickupTime ?? ''));
    final arrivalTime = _text(ride['arrival_time'] ?? ride['arrivalTime'] ?? (intercity?.arrivalTime ?? ''));
    final createdAtText = _fmtDate(ride['created_at'] ?? ride['createdAt']);
    final completedAtText = _fmtDate(ride['completed_at'] ?? ride['completedAt']);
    final rideStatus = _text(ride['status']).toLowerCase();
    final isExpired = rideStatus == 'expired';
    
    print('========== FINAL VALUES ==========');
    print('PICKUP DATE = $pickupDate');
    print('PICKUP TIME = $pickupTime');
    print('ACCEPTED ARRIVAL TIME = $arrivalTime');
    print('DISPLAY DATE = ${arrivalTime.isNotEmpty ? pickupDate : (pickupDate.isNotEmpty ? pickupDate : createdAtText.split(' ')[0].replaceAll('-', ' '))}');
    print('DISPLAY TIME = ${arrivalTime.isNotEmpty ? arrivalTime : (pickupTime.isNotEmpty ? pickupTime : createdAtText.split(' ').skip(1).join(' '))}');
    print('==================================');
    
    try {
      // ignore: avoid_print
      print('Ride Status: $rideStatus');
    } catch (_) {}

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index.clamp(0, 6) * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: child,
            ),
          ),
        );
      },
      child: GestureDetector(
        onTap: isExpired
            ? null
            : (intercity == null
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => IntercityRideMapScreen(ride: intercity!),
                      ),
                    );
                  }),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
            border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: userImage.isNotEmpty ? NetworkImage(userImage) : null,
                    radius: 22,
                    child: userImage.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                riderName.isEmpty ? 'User' : riderName,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '₹${shownPrice.toStringAsFixed(0)}',
                              style: const TextStyle(color: Color(0xFF369D01), fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 14, color: Colors.grey),
                            const SizedBox(width: 3),
                            Text(
                              '${km.toStringAsFixed(1)} Km',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.star, color: Colors.orange, size: 14),
                            const SizedBox(width: 3),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('For $persons Person${persons == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(pickup.isEmpty ? '-' : pickup, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(drop.isEmpty ? '-' : drop, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (isExpired) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'EXPIRED',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (status == 'completed') ...[
                Text(
                  'Completed: $completedAtText',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54),
                ),
              ] else ...[
                const Text(
                  'Pickup Schedule',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                if (arrivalTime.isNotEmpty) ...[
                  Row(
                    children: [
                      Text(
                        pickupDate,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        arrivalTime,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF369D01),
                        ),
                      ),
                    ],
                  ),
                ] else if (pickupDate.isNotEmpty && pickupTime.isNotEmpty) ...[
                  Row(
                    children: [
                      Text(
                        pickupDate,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        pickupTime,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF369D01),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Text(
                        createdAtText.split(' ')[0].replaceAll('-', ' '),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        createdAtText.split(' ').skip(1).join(' '),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF369D01),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 12),
              if (rideStatus == 'completed')
                Builder(
                  builder: (_) {
                    final paymentStatus = _text(ride['payment_status'] ?? ride['paymentStatus']).trim().toLowerCase();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (paymentStatus == 'completed')
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                              child: Text(
                                'Payment Completed',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Payment Pending',
                              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _confirmCashPayment(ride),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C853),
                                minimumSize: const Size(double.infinity, 45),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('RECEIVED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: _isTrue(ride['is_reviewed'])
                              ? const Center(
                                  child: Text(
                                    'Reviewed ✔',
                                    style: TextStyle(
                                      color: Color(0xFF00C853),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                )
                              : OutlinedButton(
                                  onPressed: () async {
                                    final ok = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DriverGiveReviewScreen(
                                          rideId: _text(ride['_id'] ?? ride['id']),
                                          userId: _text(
                                            ride['user_id'] ??
                                                ride['rider_id'] ??
                                                (ride['user'] is Map ? (ride['user'] as Map)['_id'] ?? (ride['user'] as Map)['id'] : null),
                                          ),
                                          userName: riderName,
                                          userImageUrl: userImage,
                                          paidAmount: shownPrice,
                                          reviewType: (_text(ride['sender_name']).isNotEmpty || _text(ride['receiver_name']).isNotEmpty)
                                              ? 'parcel'
                                              : 'driver_to_user',
                                        ),
                                      ),
                                    );

                                    if (ok == true) {
                                      if (!mounted) return;
                                      setState(() {
                                        ride['is_reviewed'] = true;
                                      });
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    side: const BorderSide(color: Color(0xFF00C853)),
                                  ),
                                  child: const Text('Review', style: TextStyle(color: Color(0xFF00C853), fontWeight: FontWeight.w900)),
                                ),
                        ),
                      ],
                    );
                  },
                )
              else if (status == 'upcoming')
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: intercity == null
                            ? null
                            : () {
                                if (rideStatus == 'started' || rideStatus == 'ongoing') {
                                  _completeRide(ride);
                                  return;
                                }

                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) => OtpVerifyDialog(
                                    ride: ride,
                                    onSuccess: refreshRideList,
                                  ),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF369D01),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          (rideStatus == 'ongoing') ? 'COMPLETE RIDE' : 'PICKUP CUSTOMER',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 46,
                      width: 54,
                      child: ElevatedButton(
                        onPressed: () {
                          final phone = _text(
                            ride['customer_phone'] ??
                                ride['rider_phone'] ??
                                ride['phone'] ??
                                ride['mobile'] ??
                                (ride['user'] is Map ? (ride['user'] as Map)['mobile'] ?? (ride['user'] as Map)['phone'] : null),
                          );
                          _callNumber(phone);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF369D01),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Icon(Icons.call),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 46,
                      width: 54,
                      child: ElevatedButton(
                        onPressed: () async {
                          final rideId = _text(ride['_id'] ?? ride['id'] ?? ride['ride_id'] ?? ride['rideId']);
                          if (rideId.isEmpty) return;

                          final receiverId = _text(
                            ride['user_id'] ??
                                ride['rider_id'] ??
                                (ride['user'] is Map ? (ride['user'] as Map)['_id'] ?? (ride['user'] as Map)['id'] : null),
                          );
                          if (receiverId.isEmpty) return;

                          final senderId = (await const SessionService().getDriverId())?.trim() ?? '';
                          if (senderId.isEmpty) return;
                          if (!context.mounted) return;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IntercityChatScreen(
                                rideId: rideId,
                                senderId: senderId,
                                receiverId: receiverId,
                                title: 'Chat',
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF369D01),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Icon(Icons.chat_bubble_outline),
                      ),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _badgeBg(status),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: _badgeFg(status)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F5F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Activity',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            Divider(height: 1, color: Colors.grey),
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 6)),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFF369D01),
                  borderRadius: BorderRadius.circular(30),
                ),
                dividerColor: Colors.transparent,
                overlayColor: MaterialStateProperty.all(Colors.transparent),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.black54,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(text: 'Upcoming'),
                  Tab(text: 'Completed'),
                  Tab(text: 'Canceled'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const BouncingScrollPhysics(),
                children: [
                  buildRideList('upcoming'),
                  buildRideList('completed'),
                  buildRideList('canceled'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OtpVerifyDialog extends StatefulWidget {
  final dynamic ride;
  final VoidCallback? onSuccess;
  const OtpVerifyDialog({super.key, required this.ride, this.onSuccess});

  @override
  State<OtpVerifyDialog> createState() => _OtpVerifyDialogState();
}

class _OtpVerifyDialogState extends State<OtpVerifyDialog> {
  final List<TextEditingController> controllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> focusNodes = List.generate(4, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    for (final f in focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _showSuccessDialog(BuildContext rootContext) {
    // STEP 2: SHOW SUCCESS DIALOG
    showDialog(
      context: rootContext,
      barrierDismissible: false,
      builder: (context) {
        // STEP 3: AUTO CLOSE AFTER 2 SECONDS
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
        });

        return Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.symmetric(horizontal: 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Color(0xFF00C853), size: 60),
                SizedBox(height: 10),
                Text(
                  "Customer Picked Up",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void verifyOtp(String otp) async {
    const green = Color(0xFF00C853);

    print("STEP 1 OTP SUBMIT: Starting OTP verification");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: green),
      ),
    );

    print("STEP 2 API CALL START: Calling verifyOtpAndStartRide API");

    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) {
        print("ERROR: Token is empty");
        Navigator.pop(context);
        _showError('Unauthorized');
        return;
      }

      final rideId = widget.ride is Map ? (widget.ride['_id'] ?? '').toString().trim() : '';
      if (rideId.isEmpty) {
        print("ERROR: Ride ID is empty");
        Navigator.pop(context);
        _showError('Ride not found');
        return;
      }

      print("STEP 3 API CALL: Token and Ride ID validated, making API call");

      final response = await const ApiService().verifyOtpAndStartRide(
        token: token,
        rideId: rideId,
        otp: otp,
      );

      print("STEP 3 API SUCCESS: API call completed");

      Navigator.pop(context); // remove loader
      print("STEP 4 LOADER CLOSED: Loader dialog removed");

      final ok = response['success'] == true || response['status'] == true;
      if (ok) {
        print("STEP 4 VERIFY RESULT TRUE: OTP verification successful");

        // STEP 5: CLOSE OTP POPUP
        print("STEP 5 CLOSE DIALOG: Closing OTP popup");
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          print("STEP 6 DIALOG CLOSED: OTP popup closed");
        }

        // Wait before showing success dialog
        await Future.delayed(const Duration(milliseconds: 150));

        print("STEP 7 SHOW SUCCESS: Showing success dialog");
        _showSuccessDialog(context);
        print("STEP 8 ON SUCCESS: Calling onSuccess callback");
        widget.onSuccess?.call();
        print("STEP 8 NAVIGATION COMPLETE: OTP flow completed");
      } else {
        print("ERROR: OTP verification failed - ${response['message']}");
        _showError((response['message'] ?? 'Invalid OTP').toString());
      }
    } catch (e) {
      print("ERROR: Exception in verifyOtp - $e");
      Navigator.pop(context);
      _showError('Something went wrong');
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF00C853);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'OTP Verify',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text('Enter OTP from customer'),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (index) {
                return SizedBox(
                  width: 50,
                  height: 55,
                  child: TextField(
                    controller: controllers[index],
                    focusNode: focusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: green, width: 1.5),
                      ),
                    ),
                    onChanged: (v) {
                      final value = v.trim();
                      if (value.isEmpty) {
                        if (index > 0) {
                          FocusScope.of(context).requestFocus(focusNodes[index - 1]);
                        }
                        return;
                      }

                      if (value.length > 1) {
                        controllers[index].text = value.substring(value.length - 1);
                        controllers[index].selection = TextSelection.fromPosition(
                          const TextPosition(offset: 1),
                        );
                      }

                      if (index < 3) {
                        FocusScope.of(context).requestFocus(focusNodes[index + 1]);
                      } else {
                        FocusScope.of(context).unfocus();
                      }
                    },
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                final otp = controllers.map((c) => c.text).join();

                if (otp.length != 4) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter valid 4-digit OTP')),
                  );
                  return;
                }

                verifyOtp(otp);
              },
              child: const Text(
                'VERIFY OTP',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
            ),
          ],
        ),
      ),
    );
  }
}


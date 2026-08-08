import 'package:flutter/material.dart';
import 'dart:async';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/screens/map_screen.dart';
import 'package:vite_captain/services/global_payment_popup.dart';
import 'package:vite_captain/services/session_service.dart';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';

class DriverPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> ride;

  const DriverPaymentScreen({
    super.key,
    required this.ride,
  });

  @override
  State<DriverPaymentScreen> createState() => _DriverPaymentScreenState();
}

class _DriverPaymentScreenState extends State<DriverPaymentScreen> {
  static const Color themeGreen = Color(0xFF22C55E);
  static const Color _darkGreen = Color(0xFF166534);

  int _selectedIndex = 0;
  bool _handled = false;
  bool _processing = false;
  bool _showWaitingCard = false;
  String _preferredMethod = '';
  Timer? _statusTimer;
  Timer? _paymentStatusTimer;
  bool _walletPopupShown = false;
  bool _paymentPopupShowing = false;

  Map<String, dynamic>? _pendingReview;

  Widget _waitingCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            children: [
              SizedBox(
                height: 26,
                width: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: themeGreen,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Waiting for customer',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 4),
                    AnimatedDotsText(),
                  ],
                ),
              ),
              Icon(Icons.schedule, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startPaymentStatusPolling() async {
    final rideId = _rideId();
    if (rideId.isEmpty) return;

    try {
      print('PAYMENT STATUS POLLING STARTED');
    } catch (_) {}

    _paymentStatusTimer?.cancel();
    _paymentStatusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        if (!mounted) return;
        if (_paymentPopupShowing) return;

        final id = _rideId();
        if (id.isEmpty) return;

        final alreadyShown = await const SessionService().getPaymentPopupShown(rideId: id);
        if (alreadyShown) {
          try {
            print('POPUP ALREADY SHOWN: rideId=$id');
          } catch (_) {}
          _paymentStatusTimer?.cancel();
          _paymentStatusTimer = null;
          return;
        }

        final res = await const ApiService().getDriverPaymentStatus(rideId: id);
        if (!mounted) return;
        if (res['success'] != true) return;

        final status = (res['payment_status'] ?? '').toString().trim().toLowerCase();
        final method = (res['payment_method'] ?? '').toString().trim().toLowerCase();
        final amountRaw = res['amount'];
        final amount = amountRaw is num ? amountRaw.toDouble() : (double.tryParse(amountRaw?.toString() ?? '') ?? 0);
        final commissionRaw = res['commission'];
        final commissionAmount = commissionRaw is num ? commissionRaw.toDouble() : (double.tryParse(commissionRaw?.toString() ?? '') ?? 0);

        if (method != 'wallet') return;
        if (status != 'user_confirmed' && status != 'completed') return;

        final alreadyShownInMemory = _walletPopupShown;
        if (status == 'user_confirmed' && !alreadyShownInMemory) {
          _walletPopupShown = true;
          try {
            print('INSTANT PAYMENT POPUP TRIGGERED');
          } catch (_) {}

          try {
            print('PAYMENT POPUP CONDITION MATCHED');
          } catch (_) {}

          try {
            await showGlobalPaymentPopup(amount: amount, commissionAmount: commissionAmount, commissionDeducted: commissionAmount > 0);
          } catch (_) {}
          return;
        }

        try {
          print('INSTANT PAYMENT POPUP TRIGGERED');
        } catch (_) {}

        try {
          print('PAYMENT POPUP CONDITION MATCHED');
        } catch (_) {}

        _paymentPopupShowing = true;
        if (status == 'completed') {
          try {
            await const SessionService().setPaymentPopupShown(rideId: id, value: true);
          } catch (_) {}
        }

        try {
          try {
            await AudioPlayer().play(AssetSource('sounds/beep.mp3'));
          } catch (_) {}

          try {
            final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
            if (driverId.isNotEmpty) {
              final w = await const ApiService().getDriverWallet(driverId: driverId);
              if (w['success'] == true) {
                final b = (w['balance'] as num?)?.toDouble() ?? 0.0;
                await const SessionService().saveWalletBalance(b);
                try {
                  print('DRIVER WALLET UPDATED: $b');
                } catch (_) {}
              }
            }
          } catch (_) {}

          try {
            final c = await const ApiService().walletReceivedRide(rideId: id);
            if (c['success'] == true) {
              try {
                print('COMMISSION DEDUCTED');
              } catch (_) {}
            }
          } catch (_) {}

          try {
            print('DRIVER PAYMENT POPUP SHOWN');
          } catch (_) {}

          await showGlobalPaymentPopup(amount: amount, commissionAmount: commissionAmount, commissionDeducted: commissionAmount > 0);
        } catch (_) {
          // ignore
        } finally {
          _paymentStatusTimer?.cancel();
          _paymentStatusTimer = null;
          _paymentPopupShowing = false;

          try {
            print('PAYMENT POLLING STOPPED');
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  Future<void> _goHome() async {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => MapScreen()),
      (route) => false,
    );
  }

  Future<void> _showPaidBottomSheet({
    required String rideId,
    required double paidAmount,
    required String profileName,
    required String profileImageUrl,
  }) async {
    if (!mounted) return;

    int rating = 0;
    final Set<String> selectedTags = <String>{};
    final textController = TextEditingController();
    bool submitting = false;

    bool hasImage(String url) {
      final v = url.trim();
      return v.startsWith('http://') || v.startsWith('https://');
    }

    Future<void> submitReview(BuildContext sheetContext) async {
      if (submitting) return;
      submitting = true;

      (sheetContext as Element).markNeedsBuild();

      try {
        final parts = <String>[];
        if (selectedTags.isNotEmpty) parts.addAll(selectedTags);
        final freeText = textController.text.trim();
        if (freeText.isNotEmpty) parts.add(freeText);
        final comment = parts.join(parts.length > 1 ? ' • ' : '');

        final res = await const ApiService().submitReview(
          rideId: rideId,
          rating: rating,
          comment: comment,
        );
        final ok = res['success'] == true;

        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();

        if (!ok) {
          final msg = (res['message'] ?? 'Failed to submit review').toString();
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(SnackBar(content: Text(msg)));
          await _goHome();
          return;
        }

        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Review submitted successfully',
                    style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );

        await Future.delayed(const Duration(seconds: 2));
        await _goHome();
      } catch (_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).maybePop();
        await _goHome();
      }
    }

    Future<void> skipReview() async {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await _goHome();
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final displayName = profileName.trim().isEmpty ? 'Driver' : profileName.trim();
        final url = profileImageUrl.trim();

        Widget chip(String text) {
          final selected = selectedTags.contains(text);
          return InkWell(
            onTap: () {
              if (submitting) return;
              if (selected) {
                selectedTags.remove(text);
              } else {
                selectedTags.add(text);
              }
              (sheetContext as Element).markNeedsBuild();
            },
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? themeGreen.withOpacity(0.12) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selected ? themeGreen : Colors.transparent),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? themeGreen : Colors.black87,
                ),
              ),
            ),
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(color: Colors.black.withOpacity(0.25)),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        18,
                        10,
                        18,
                        MediaQuery.of(sheetContext).viewInsets.bottom + 10,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Container(
                            height: 4,
                            width: 40,
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.check_circle, color: themeGreen),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Paid \u20B9${paidAmount.toStringAsFixed(2)}',
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                          ),
                                        ],
                                      ),
                                      TextButton.icon(
                                        onPressed: () {},
                                        icon: const Icon(Icons.help_outline, color: themeGreen),
                                        label: const Text(
                                          'Help',
                                          style: TextStyle(color: themeGreen, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  CircleAvatar(
                                    radius: 42,
                                    backgroundColor: themeGreen.withOpacity(0.12),
                                    child: hasImage(url)
                                        ? ClipOval(
                                            child: Image.network(
                                              url,
                                              width: 84,
                                              height: 84,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return const Icon(Icons.person, size: 46, color: Colors.black87);
                                              },
                                            ),
                                          )
                                        : Text(
                                            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'D',
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.black87),
                                          ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    displayName,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'How was your ride with $displayName',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(5, (index) {
                                      final filled = index < rating;
                                      return IconButton(
                                        onPressed: submitting
                                            ? null
                                            : () {
                                                rating = index + 1;
                                                (sheetContext as Element).markNeedsBuild();
                                              },
                                        icon: Icon(
                                          filled ? Icons.star : Icons.star_border,
                                          size: 34,
                                          color: filled ? themeGreen : Colors.grey.shade300,
                                        ),
                                      );
                                    }),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Great, what did you like the most?',
                                    style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      chip('Comfortable ride'),
                                      chip('Professional ride'),
                                      chip('Affordable'),
                                      chip('Clean Helmet'),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: textController,
                                    enabled: !submitting,
                                    enableInteractiveSelection: false,
                                    decoration: InputDecoration(
                                      hintText: 'Tell us more...',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: themeGreen, width: 1.4),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Column(
                                    children: [
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: themeGreen,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onPressed: submitting ? null : () => submitReview(sheetContext),
                                          child: submitting
                                              ? const SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                )
                                              : const Text('Done', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: themeGreen),
                                            foregroundColor: themeGreen,
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onPressed: submitting ? null : skipReview,
                                          child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return const <String, dynamic>{};
  }

  String _rideId() {
    String fromMap(Map<String, dynamic> m) {
      return (m['ride_id'] ?? m['_id'] ?? m['id'] ?? m['rideId'] ?? '').toString().trim();
    }

    final direct = fromMap(widget.ride);
    if (direct.isNotEmpty) return direct;

    final nestedKeys = <String>['ride', 'rideData', 'booking', 'bookingData', 'request', 'data', 'details'];
    for (final k in nestedKeys) {
      final m = _asMap(widget.ride[k]);
      final v = fromMap(m);
      if (v.isNotEmpty) return v;
    }

    return '';
  }

  int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> _showProcessingDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return WillPopScope(
          onWillPop: () async => false,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }

  Future<void> _handleReceived() async {
    if (_processing || _handled) return;
    final rideId = _rideId();
    if (rideId.isEmpty) return;
    _processing = true;

    print('RECEIVED BUTTON CLICKED');
    print('RIDE ID: $rideId');

    // Determine ride type
    final rideType = (widget.ride['ride_type'] ?? widget.ride['rideType'] ?? 'normal').toString().trim();
    print('RECEIVED BUTTON - RIDE TYPE: $rideType');
    print('RECEIVED BUTTON - RIDE ID: $rideId');

    _showProcessingDialog();

    try {
      final methodRaw = (widget.ride['payment_method'] ?? widget.ride['paymentMethod'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final shouldWallet = _preferredMethod == 'wallet' || methodRaw == 'wallet';
      final token = (await const SessionService().getToken())?.trim() ?? '';

      print('RECEIVED BUTTON - PAYMENT METHOD: ${shouldWallet ? "wallet" : "cash"}');

      final res = shouldWallet
          ? await const ApiService().walletReceivedRide(rideId: rideId)
          : await const ApiService().confirmCashReceived(rideId: rideId, token: token, rideType: rideType);
      print('API RESPONSE: $res');
      final ok = res['success'] == true;
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      if (!ok) {
        _processing = false;
        final msg = (res['message'] ?? 'Payment failed').toString();
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      _processing = false;
      _handled = true;
      if (mounted) {
        setState(() {
          _showWaitingCard = false;
        });
      }

      try {
        await const SessionService().setPaymentPopupShown(rideId: rideId, value: true);
      } catch (_) {}

      _startPaymentStatusPolling();

      final userNode = widget.ride['user'];
      final userMap = userNode is Map ? userNode : const {};
      final userName = (widget.ride['user_name'] ?? userMap['name'] ?? widget.ride['customerName'] ?? widget.ride['userName'] ?? widget.ride['name'] ?? 'Customer')
          .toString()
          .trim();
      final userImageUrl = (widget.ride['user_image'] ?? widget.ride['userImage'] ?? (userMap['profile_image'] ?? '') ?? '')
          .toString()
          .trim();

      final fareValue = widget.ride['finalFare'] ?? widget.ride['fare'] ?? widget.ride['fare_amount'] ?? widget.ride['amount'];
      final paidAmount = fareValue is num ? fareValue.toDouble() : (double.tryParse(fareValue?.toString() ?? '') ?? 0);

      if (!mounted) return;
      _pendingReview = {
        'rideId': rideId,
        'paidAmount': paidAmount,
        'profileName': userName,
        'profileImageUrl': userImageUrl,
      };

      try {
        print('NOW OPENING REVIEW SCREEN');
      } catch (_) {}

      final pending = _pendingReview;
      if (pending != null && mounted) {
        _pendingReview = null;
        await _showPaidBottomSheet(
          rideId: (pending['rideId'] ?? '').toString(),
          paidAmount: (pending['paidAmount'] as num?)?.toDouble() ?? 0.0,
          profileName: (pending['profileName'] ?? '').toString(),
          profileImageUrl: (pending['profileImageUrl'] ?? '').toString(),
        );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).maybePop();
      _processing = false;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Payment failed')));
    }
  }

  @override
  void initState() {
    super.initState();

    final rideId = _rideId();
    if (rideId.isEmpty) return;

    final initMethodRaw = (widget.ride['payment_method'] ?? widget.ride['paymentMethod'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (initMethodRaw == 'wallet') {
      _preferredMethod = 'wallet';
    }

    _startPaymentStatusPolling();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        if (!mounted) return;
        if (_walletPopupShown || _handled) return;

        final id = _rideId();
        if (id.isEmpty) return;

        final res = await const ApiService().getRideDetails(rideId: id);
        if (!mounted) return;
        if (res['success'] != true) return;

        final data = res['data'] is Map ? Map<String, dynamic>.from(res['data']) : <String, dynamic>{};
        final status = (data['payment_status'] ?? data['paymentStatus'] ?? '').toString().trim().toLowerCase();
        final method = (data['payment_method'] ?? data['paymentMethod'] ?? '').toString().trim().toLowerCase();
        final amountRaw = data['amount'] ?? data['fare'] ?? data['finalFare'];
        final amount = amountRaw is num ? amountRaw.toDouble() : (double.tryParse(amountRaw?.toString() ?? '') ?? 0);

        if (status == 'user_confirmed' && method == 'wallet') {
          _walletPopupShown = true;
          if (!mounted) return;
          setState(() {
            _showWaitingCard = true;
            _preferredMethod = 'wallet';
          });

          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.black.withOpacity(0.85),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Text('Wallet payment received: \u20B9${amount.toStringAsFixed(0)}. Tap Received to confirm.'),
              duration: const Duration(seconds: 4),
            ),
          );

          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (ctx) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Payment Received'),
                content: Text('Wallet payment of \u20B9${amount.toStringAsFixed(0)} received.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        }
      } catch (_) {}
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final methodRaw = (widget.ride['payment_method'] ?? widget.ride['paymentMethod'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final isWallet = methodRaw == 'wallet';
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black.withOpacity(0.85),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.info, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isWallet
                      ? "When wallet payment is received, tap 'Received' to confirm."
                      : "When cash is received, tap 'Received'",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _paymentStatusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userNode = widget.ride['user'];
    final userMap = userNode is Map ? userNode : const {};

    final riderName = (widget.ride['user_name'] ?? userMap['name'] ?? widget.ride['customerName'] ?? widget.ride['userName'] ?? widget.ride['name'] ?? 'Customer')
        .toString()
        .trim();

    final userImageUrl = (widget.ride['user_image'] ?? widget.ride['userImage'] ?? (userMap['profile_image'] ?? '') ?? '')
        .toString()
        .trim();
    final hasUserImage = userImageUrl.startsWith('http://') || userImageUrl.startsWith('https://');

    final fareValue = widget.ride['finalFare'] ?? widget.ride['fare'] ?? widget.ride['fare_amount'] ?? widget.ride['amount'];
    final fare = fareValue is num ? fareValue.toDouble() : (double.tryParse(fareValue?.toString() ?? '') ?? 0);

    final pickupMap = _asMap(widget.ride['pickup']);
    final dropMap = _asMap(widget.ride['drop']);
    final pickupAddress = (widget.ride['pickup_address'] ?? pickupMap['address'] ?? widget.ride['pickupAddress'] ?? 'Pickup location').toString().trim();
    final dropAddress = (widget.ride['drop_address'] ?? dropMap['address'] ?? widget.ride['dropAddress'] ?? 'Drop location').toString().trim();

    final distanceKm = _asDouble(widget.ride['distance'] ?? widget.ride['totalDistance'] ?? widget.ride['total_distance'] ?? widget.ride['distance_km']);
    final totalTimeMin = _asDouble(widget.ride['total_time'] ?? widget.ride['total_time_minutes'] ?? widget.ride['totalTime'] ?? widget.ride['totalTimeMinutes']);

    final methodsRaw = widget.ride['payment_methods'] ?? widget.ride['paymentMethods'];
    final methods = (methodsRaw is List)
        ? methodsRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList(growable: false)
        : <String>[];
    final normalized = methods
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final filtered = normalized.where((m) {
      final l = m.toLowerCase();
      return l.contains('cash') || l.contains('wallet');
    }).toList(growable: false);
    final paymentMethods = filtered.isNotEmpty ? filtered : const <String>['Cash', 'Wallet'];
    final walletIndex = paymentMethods.indexWhere((m) => m.toLowerCase().contains('wallet'));
    final effectiveIndex = (_preferredMethod == 'wallet' && walletIndex >= 0)
        ? walletIndex
        : _selectedIndex.clamp(0, paymentMethods.length - 1);
    final selectedMethod = paymentMethods[effectiveIndex];

    final buttonEnabled = !_processing;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: const Text('Payment', style: TextStyle(color: Colors.black)),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 35,
                              backgroundColor: themeGreen,
                              child: hasUserImage
                                  ? ClipOval(
                                      child: Image.network(
                                        userImageUrl,
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Text(
                                            riderName.isNotEmpty ? riderName[0].toUpperCase() : 'C',
                                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                                          );
                                        },
                                      ),
                                    )
                                  : Text(
                                      riderName.isNotEmpty ? riderName[0].toUpperCase() : 'C',
                                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.check, color: Colors.green, size: 16),
                                  SizedBox(width: 5),
                                  Text('RIDE COMPLETED', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Select a payment method to pay',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              riderName,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '\u20B9${fare.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 15),
                            if (distanceKm > 0 || totalTimeMin > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('${distanceKm.toStringAsFixed(2)} km', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text('${totalTimeMin.round()} min', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Base fare'),
                                Text('\u20B9${fare.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Final fare'),
                                Text('\u20B9${fare.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pay via', style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            ...List<Widget>.generate(paymentMethods.length, (i) {
                              final title = paymentMethods[i];
                              final lower = title.toLowerCase();
                              final icon = lower.contains('cash')
                                  ? Icons.money
                                  : (lower.contains('wallet') ? Icons.account_balance_wallet : Icons.payment);
                              final color = themeGreen;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(icon, color: color),
                                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                trailing: Radio<int>(
                                  value: i,
                                  groupValue: effectiveIndex,
                                  onChanged: (v) {
                                    if (v == null) return;
                                    final chosen = paymentMethods[v].toLowerCase();
                                    setState(() {
                                      _preferredMethod = chosen.contains('wallet')
                                          ? 'wallet'
                                          : (chosen.contains('cash') ? 'cash' : '');
                                      _selectedIndex = v;
                                    });
                                  },
                                ),
                                onTap: () {
                                  final chosen = paymentMethods[i].toLowerCase();
                                  setState(() {
                                    _preferredMethod = chosen.contains('wallet')
                                        ? 'wallet'
                                        : (chosen.contains('cash') ? 'cash' : '');
                                    _selectedIndex = i;
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    color: Colors.transparent,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: buttonEnabled ? themeGreen : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _handleReceived,
                      child: const Text('Received', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ),
                ],
              ),
              Positioned(
                bottom: 96,
                left: 16,
                right: 16,
                child: AnimatedSlide(
                  offset: _showWaitingCard ? Offset.zero : const Offset(0, 0.2),
                  duration: const Duration(milliseconds: 400),
                  child: AnimatedOpacity(
                    opacity: _showWaitingCard ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: IgnorePointer(
                      ignoring: !_showWaitingCard,
                      child: _waitingCard(),
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

class AnimatedDotsText extends StatefulWidget {
  const AnimatedDotsText({super.key});

  @override
  State<AnimatedDotsText> createState() => _AnimatedDotsTextState();
}

class _AnimatedDotsTextState extends State<AnimatedDotsText> {
  int dotCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {
        dotCount = (dotCount + 1) % 4;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * dotCount;
    return Text(
      'Confirming payment$dots',
      style: const TextStyle(
        fontSize: 13,
        color: Colors.grey,
      ),
    );
  }
}


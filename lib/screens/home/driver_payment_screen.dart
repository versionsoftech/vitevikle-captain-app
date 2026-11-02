import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/screens/map_screen.dart';
import 'package:vite_captain/screens/home/online_payment_success_screen.dart';
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
  static const Color themeGreen = Color(0xFF009640);
  static const Color _darkGreen = Color(0xFF009640);

  int _selectedIndex = 0;
  bool _handled = false;
  bool _processing = false;
  bool _showWaitingCard = false;
  String _preferredMethod = '';
  Timer? _statusTimer;
  Timer? _paymentStatusTimer;
  bool _walletPopupShown = false;
  bool _onlineAutoConfirm = false;
  bool _onlineSuccessShown = false;
  bool _paymentPopupShowing = false;
  io.Socket? _paySocket;

  Map<String, dynamic>? _pendingReview;

  Widget _waitingCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
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
                child: ViteLoader(
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
            final rideType = (widget.ride['ride_type'] ?? widget.ride['rideType'] ?? 'normal').toString().trim();
            final c = await const ApiService().walletReceivedRide(rideId: id, rideType: rideType.isEmpty ? 'normal' : rideType);
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

  String _textFromRide(List<String> keys, {String fallback = ''}) {
    for (final key in keys) {
      final value = widget.ride[key];
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text != 'null') return text;
    }
    return fallback;
  }

  Future<void> _openOnlinePaid({double amount = 0}) async {
    if (_onlineSuccessShown || !mounted) return;
    _onlineSuccessShown = true;
    _handled = true;
    _onlineAutoConfirm = true;
    _statusTimer?.cancel();
    _paymentStatusTimer?.cancel();

    final rideId = _rideId();
    final rideType = (widget.ride['ride_type'] ?? widget.ride['rideType'] ?? 'normal').toString().trim();
    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (rideId.isNotEmpty && token.isNotEmpty) {
        unawaited(const ApiService().confirmCashReceived(
          rideId: rideId,
          token: token,
          rideType: rideType.isEmpty ? 'normal' : rideType,
        ));
      }
    } catch (_) {}

    if (!mounted) return;
    final userNode = widget.ride['user'];
    final userMap = userNode is Map ? Map<String, dynamic>.from(userNode) : const <String, dynamic>{};
    final riderName = _textFromRide(
      const ['user_name', 'customerName', 'userName', 'name'],
      fallback: (userMap['name'] ?? 'Rider').toString(),
    );
    final pickupMap = _asMap(widget.ride['pickup']);
    final dropMap = _asMap(widget.ride['drop']);
    final pickupRaw = widget.ride['pickup'];
    final dropRaw = widget.ride['drop'];
    final pickup = _textFromRide(
      const ['pickup_address', 'pickupAddress', 'pickup_location'],
      fallback: (pickupMap['address'] ?? (pickupRaw is String ? pickupRaw : '')).toString(),
    );
    final drop = _textFromRide(
      const ['drop_address', 'dropAddress', 'drop_location'],
      fallback: (dropMap['address'] ?? (dropRaw is String ? dropRaw : '')).toString(),
    );
    final fareValue = widget.ride['finalFare'] ?? widget.ride['fare'] ?? widget.ride['fare_amount'] ?? widget.ride['amount'] ?? widget.ride['total_price'] ?? widget.ride['accepted_fare'] ?? widget.ride['price'];
    final localFare = fareValue is num ? fareValue.toDouble() : (double.tryParse(fareValue?.toString() ?? '') ?? 0);
    final shown = amount > 0 ? amount : localFare;

    final socket = _paySocket;
    _paySocket = null;
    final userImageUrl = (widget.ride['user_image'] ?? widget.ride['userImage'] ?? userMap['profile_image'] ?? '').toString().trim();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OnlinePaymentSuccessScreen(
          amount: shown,
          riderName: riderName,
          pickup: pickup,
          drop: drop,
          paymentId: rideId.length > 8 ? rideId.substring(rideId.length - 8).toUpperCase() : rideId.toUpperCase(),
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      try {
        socket?.dispose();
      } catch (_) {}
    });
    if (!mounted) return;
    await _showPaidBottomSheet(
      rideId: rideId,
      paidAmount: shown,
      profileName: riderName,
      profileImageUrl: userImageUrl,
    );
  }

  void _listenOnlinePayment() {
    final rideId = _rideId();
    if (rideId.isEmpty || _paySocket != null) return;
    try {
      final socket = io.io(
        'https://adm.vitevikle.com',
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': false,
          'reconnection': true,
        },
      );
      _paySocket = socket;

      void onPaid(dynamic data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        final incoming = (map['ride_id'] ?? map['rideId'] ?? '').toString().trim();
        if (incoming.isNotEmpty && incoming != rideId) return;
        final amountRaw = map['amount'] ?? map['fare'] ?? map['finalFare'];
        final amount = amountRaw is num ? amountRaw.toDouble() : (double.tryParse(amountRaw?.toString() ?? '') ?? 0);
        _openOnlinePaid(amount: amount);
      }

      socket.on('connect', (_) {
        socket.emit('join_ride', {'ride_id': rideId});
        socket.emit('joinRide', {'rideId': rideId});
      });
      socket.on('online_payment_received', onPaid);
      socket.on('paymentStatusChanged', (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        final method = (map['payment_method'] ?? map['paymentMethod'] ?? '').toString().trim().toLowerCase();
        final status = (map['payment_status'] ?? map['paymentStatus'] ?? '').toString().trim().toLowerCase();
        final online = method == 'razorpay' || method == 'online';
        final paid = status == 'user_confirmed' || status == 'paid' || status == 'completed';
        if (online && paid) onPaid(data);
      });
      socket.connect();
      socket.emit('join_ride', {'ride_id': rideId});
      socket.emit('joinRide', {'rideId': rideId});
    } catch (_) {
      _paySocket = null;
    }
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
            backgroundColor: const Color(0xFF009640),
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
      isDismissible: false,
      enableDrag: false,
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
                child: Container(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.25)),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
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
                                      Flexible(
                                        child: Row(
                                          children: [
                                            const Icon(Icons.check_circle, color: themeGreen),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Paid \u20B9${paidAmount.toStringAsFixed(2)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () {},
                                        icon: const Icon(Icons.help_outline, color: themeGreen, size: 18),
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
                                                return Icon(Icons.person, size: 46, color: Theme.of(context).colorScheme.onSurface);
                                              },
                                            ),
                                          )
                                        : Text(
                                            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'D',
                                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Theme.of(context).colorScheme.onSurface),
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
                                      return GestureDetector(
                                        onTap: submitting
                                            ? null
                                            : () {
                                                rating = index + 1;
                                                (sheetContext as Element).markNeedsBuild();
                                              },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 3),
                                          child: Icon(
                                            filled ? Icons.star : Icons.star_border,
                                            size: 32,
                                            color: filled ? themeGreen : Colors.grey.shade300,
                                          ),
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
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: TextField(
                                      controller: textController,
                                      enabled: !submitting,
                                      enableInteractiveSelection: false,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: 'Tell us more...',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: themeGreen, width: 1.4),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: Column(
                                      children: [
                                        Material(
                                          color: themeGreen,
                                          borderRadius: BorderRadius.circular(12),
                                          child: InkWell(
                                            onTap: submitting ? null : () => submitReview(sheetContext),
                                            borderRadius: BorderRadius.circular(12),
                                            child: SizedBox(
                                              height: 48,
                                              width: double.infinity,
                                              child: Center(
                                                child: submitting
                                                    ? const SizedBox(height: 20, width: 20, child: ViteLoader(strokeWidth: 2, color: Colors.white))
                                                    : const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: submitting ? null : skipReview,
                                            borderRadius: BorderRadius.circular(12),
                                            child: Ink(
                                              height: 48,
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: themeGreen),
                                              ),
                                              child: const Center(
                                                child: Text('Skip', style: TextStyle(color: themeGreen, fontWeight: FontWeight.w900, fontSize: 16)),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
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
    final text = (v ?? '').toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(text) ?? 0;
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
            child: ViteLoader(),
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
      final online = _preferredMethod == 'razorpay' || methodRaw == 'razorpay' || methodRaw == 'online';
      final shouldWallet = !online && (_preferredMethod == 'wallet' || methodRaw == 'wallet');
      final token = (await const SessionService().getToken())?.trim() ?? '';

      print('RECEIVED BUTTON - PAYMENT METHOD: ${shouldWallet ? "wallet" : "cash"}');

      final res = shouldWallet
          ? await const ApiService().walletReceivedRide(rideId: rideId, rideType: rideType)
          : await const ApiService().confirmCashReceived(rideId: rideId, token: token, rideType: rideType);
      print('API RESPONSE: $res');
      final ok = res['success'] == true;
      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      if (!ok) {
        _processing = false;
        final rawMsg = (res['message'] ?? 'Payment failed').toString();
        final lowerMsg = rawMsg.toLowerCase();
        final msg = (rawMsg.trim().isEmpty || lowerMsg.contains('<!doctype') || lowerMsg.contains('<html') || lowerMsg.contains('cannot post'))
            ? 'Could not confirm the payment. Please try again.'
            : rawMsg;
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

      final fareValue = widget.ride['finalFare'] ?? widget.ride['fare'] ?? widget.ride['fare_amount'] ?? widget.ride['amount'] ?? widget.ride['total_price'] ?? widget.ride['accepted_fare'] ?? widget.ride['price'];
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
    } else if (initMethodRaw == 'razorpay' || initMethodRaw == 'online') {
      _preferredMethod = 'razorpay';
    }

    _startPaymentStatusPolling();
    _listenOnlinePayment();
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

        final online = method == 'razorpay' || method == 'online';
        final paid = status == 'user_confirmed' || status == 'paid' || status == 'completed';
        if (online && paid && !_onlineSuccessShown && !_handled && !_processing) {
          _preferredMethod = 'razorpay';
          await _openOnlinePaid(amount: amount);
          return;
        }

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
      final isOnline = methodRaw == 'razorpay' || methodRaw == 'online';
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
                  isOnline
                      ? "Waiting for the rider to pay online."
                      : isWallet
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
    try {
      _paySocket?.dispose();
    } catch (_) {}
    _paySocket = null;
    super.dispose();
  }

  Widget _payStop({required Color color, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          height: 10,
          width: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text.trim().isEmpty ? 'Location' : text.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13.5),
          ),
        ),
      ],
    );
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

    final fareValue = widget.ride['finalFare'] ?? widget.ride['fare'] ?? widget.ride['fare_amount'] ?? widget.ride['amount'] ?? widget.ride['total_price'] ?? widget.ride['accepted_fare'] ?? widget.ride['price'];
    final fare = fareValue is num ? fareValue.toDouble() : (double.tryParse(fareValue?.toString() ?? '') ?? 0);

    final pickupMap = _asMap(widget.ride['pickup']);
    final dropMap = _asMap(widget.ride['drop']);
    final pickupRaw = widget.ride['pickup'];
    final dropRaw = widget.ride['drop'];
    final pickupAddress = (widget.ride['pickup_address'] ?? pickupMap['address'] ?? widget.ride['pickupAddress'] ?? widget.ride['pickup_location'] ?? (pickupRaw is String ? pickupRaw : null) ?? 'Pickup location').toString().trim();
    final dropAddress = (widget.ride['drop_address'] ?? dropMap['address'] ?? widget.ride['dropAddress'] ?? widget.ride['drop_location'] ?? (dropRaw is String ? dropRaw : null) ?? 'Drop location').toString().trim();

    final distanceKm = _asDouble(widget.ride['distance'] ?? widget.ride['totalDistance'] ?? widget.ride['total_distance'] ?? widget.ride['distance_km'] ?? widget.ride['total_km'] ?? widget.ride['km']);
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
      return l.contains('cash') || l.contains('wallet') || l.contains('razor') || l.contains('online');
    }).toList(growable: false);
    final paymentMethods = filtered.isNotEmpty ? List<String>.from(filtered) : <String>['Cash', 'Wallet'];
    if (!paymentMethods.any((m) {
      final l = m.toLowerCase();
      return l.contains('razor') || l.contains('online');
    })) {
      paymentMethods.add('Razorpay');
    }
    final walletIndex = paymentMethods.indexWhere((m) => m.toLowerCase().contains('wallet'));
    final onlineIndex = paymentMethods.indexWhere((m) {
      final l = m.toLowerCase();
      return l.contains('razor') || l.contains('online');
    });
    final effectiveIndex = (_preferredMethod == 'razorpay' && onlineIndex >= 0)
        ? onlineIndex
        : (_preferredMethod == 'wallet' && walletIndex >= 0)
        ? walletIndex
        : _selectedIndex.clamp(0, paymentMethods.length - 1);
    final selectedMethod = paymentMethods[effectiveIndex];

    final buttonEnabled = !_processing;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: Text('Payment', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
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
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                _payStop(color: themeGreen, text: pickupAddress),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const SizedBox(width: 16),
                                    if (distanceKm > 0)
                                      Text('${distanceKm.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    if (distanceKm > 0) const SizedBox(width: 12),
                                    if (totalTimeMin > 0)
                                      Text('${totalTimeMin.round()} min', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _payStop(color: const Color(0xFFEF4444), text: dropAddress),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
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
                                color: const Color(0xFFDFF5E8),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.check, color: const Color(0xFF009640), size: 16),
                                  SizedBox(width: 5),
                                  Text('RIDE COMPLETED', style: TextStyle(color: const Color(0xFF009640), fontWeight: FontWeight.w800)),
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
                          color: Theme.of(context).colorScheme.surface,
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
                              final asset = lower.contains('cash')
                                  ? 'assets/images/payments/cash.png'
                                  : (lower.contains('wallet') ? 'assets/images/payments/wallet.png' : '');
                              final icon = lower.contains('cash')
                                  ? Icons.money
                                  : (lower.contains('wallet') ? Icons.account_balance_wallet : Icons.payment);
                              final color = themeGreen;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  height: 42,
                                  width: 42,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: asset.isEmpty
                                      ? Icon(icon, color: color, size: 22)
                                      : Image.asset(
                                          asset,
                                          height: 24,
                                          width: 24,
                                          errorBuilder: (_, __, ___) => Icon(icon, color: color, size: 22),
                                        ),
                                ),
                                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                trailing: Radio<int>(
                                  value: i,
                                  groupValue: effectiveIndex,
                                  onChanged: (v) {
                                    if (v == null) return;
                                    final chosen = paymentMethods[v].toLowerCase();
                                    setState(() {
                                      _preferredMethod = chosen.contains('razor') || chosen.contains('online')
                                          ? 'razorpay'
                                          : chosen.contains('wallet')
                                          ? 'wallet'
                                          : (chosen.contains('cash') ? 'cash' : '');
                                      _selectedIndex = v;
                                    });
                                  },
                                ),
                                onTap: () {
                                  final chosen = paymentMethods[i].toLowerCase();
                                  setState(() {
                                    _preferredMethod = chosen.contains('razor') || chosen.contains('online')
                                        ? 'razorpay'
                                        : chosen.contains('wallet')
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


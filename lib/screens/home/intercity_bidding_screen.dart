import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:vite_captain/models/intercity_request.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/app_config.dart';
import 'package:vite_captain/widgets/wallet_insufficient_dialog.dart';

class IntercityBiddingScreen extends StatefulWidget {
  final IntercityRequestModel ride;

  const IntercityBiddingScreen({
    super.key,
    required this.ride,
  });

  @override
  State<IntercityBiddingScreen> createState() => _IntercityBiddingScreenState();
}

class _IntercityBiddingScreenState extends State<IntercityBiddingScreen> {
  static const Color _green = Color(0xFF009640);

  final SessionService _sessionService = const SessionService();
  late final TextEditingController _fareCtrl;

  bool _loading = false;
  double _fare = 0;

  String _driverName = '';
  String _driverImage = '';
  double _driverRating = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.ride.bidPrice > 0 ? widget.ride.bidPrice : widget.ride.price;
    _fare = initial <= 0 ? 0 : initial;
    _fareCtrl = TextEditingController(text: _fare <= 0 ? '' : _fare.toStringAsFixed(0));
    _hydrateDriverBasics();
  }

  @override
  void dispose() {
    _fareCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrateDriverBasics() async {
    try {
      final basics = await _sessionService.getUserBasics();
      if (!mounted) return;
      setState(() {
        _driverName = (basics['name'] ?? '').trim();
        _driverImage = (basics['imageUrl'] ?? '').trim();
      });
    } catch (_) {
      return;
    }
  }

  String _money(double v) {
    final n = v.isFinite ? v : 0;
    return n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2);
  }

  void _setFare(double next) {
    final double normalized = next < 0 ? 0.0 : next;
    setState(() {
      _fare = normalized;
      _fareCtrl.text = _fare <= 0 ? '' : _fare.toStringAsFixed(0);
      _fareCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _fareCtrl.text.length));
    });
  }

  Future<void> _submit() async {
    if (_loading) return;
    final rideId = widget.ride.id.trim();
    if (rideId.isEmpty) return;

    final fare = _fare;
    if (fare <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid fare')),
      );
      return;
    }

    final maxBid = AppConfig.numRideSetting('maximum_bidding_fare_driver', 0).toDouble();
    if (maxBid > 0 && fare > maxBid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Max bid allowed is ₹${maxBid.toStringAsFixed(0)}')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unauthorized')),
        );
        return;
      }

      final resp = await const ApiService().sendIntercityBid(
        token: token,
        rideId: rideId,
        price: fare,
        timeMinutes: widget.ride.timeMinutes > 0 ? widget.ride.timeMinutes : null,
      );

      if (!mounted) return;
      final ok = resp['success'] == true;
      if (!ok) {
        final msg = (resp['message'] ?? 'Failed to send bid').toString();
        if (isWalletInsufficientMessage(msg)) {
          await showWalletInsufficientDialog(context, message: msg);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text('OutStation', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: IntercityBidBottomSheet(ride: widget.ride),
    );
  }
}

class IntercityBidBottomSheet extends StatefulWidget {
  final IntercityRequestModel ride;

  const IntercityBidBottomSheet({
    super.key,
    required this.ride,
  });

  @override
  State<IntercityBidBottomSheet> createState() => _IntercityBidBottomSheetState();
}

class _IntercityBidBottomSheetState extends State<IntercityBidBottomSheet> {
  static const Color _green = Color(0xFF009640);

  final SessionService _sessionService = const SessionService();
  late final TextEditingController _fareCtrl;

  bool _loading = false;
  double _fare = 0;

  String _driverName = '';
  String _driverImage = '';
  double _driverRating = 0;

  int selectedHour = DateTime.now().hour;
  int selectedMinute = DateTime.now().minute;
  String period = 'AM';

  @override
  void initState() {
    super.initState();
    final initial = widget.ride.bidPrice > 0 ? widget.ride.bidPrice : widget.ride.price;
    _fare = initial <= 0 ? 0 : initial;
    _fareCtrl = TextEditingController(text: _fare <= 0 ? '' : _fare.toStringAsFixed(0));
    _hydrateDriverBasics();
    _initializeTime();
  }

  void _initializeTime() {
    final now = DateTime.now();
    selectedHour = now.hour;
    selectedMinute = now.minute;
    period = selectedHour >= 12 ? 'PM' : 'AM';
    if (selectedHour > 12) selectedHour -= 12;
    if (selectedHour == 0) selectedHour = 12;
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _selectedTimeText() {
    return '${_two(selectedHour)}:${_two(selectedMinute)} $period';
  }

  int _selectedTimeMinutes() {
    int hour24 = selectedHour;
    if (period == 'PM' && selectedHour != 12) hour24 += 12;
    if (period == 'AM' && selectedHour == 12) hour24 = 0;
    return (hour24 * 60) + selectedMinute;
  }

  @override
  void dispose() {
    _fareCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrateDriverBasics() async {
    try {
      final basics = await _sessionService.getUserBasics();
      if (!mounted) return;
      setState(() {
        _driverName = (basics['name'] ?? '').trim();
        _driverImage = (basics['imageUrl'] ?? '').trim();
      });
    } catch (_) {
      return;
    }
  }

  String _money(double v) {
    final n = v.isFinite ? v : 0;
    return n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2);
  }

  void _setFare(double next) {
    final double normalized = next < 0 ? 0.0 : next;
    setState(() {
      _fare = normalized;
      _fareCtrl.text = _fare <= 0 ? '' : _fare.toStringAsFixed(0);
      _fareCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _fareCtrl.text.length));
    });
  }

  Future<void> _submit() async {
    if (_loading) return;
    final rideId = widget.ride.id.trim();
    if (rideId.isEmpty) return;

    final fare = _fare;
    if (fare <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid fare')),
      );
      return;
    }

    final maxBid = AppConfig.numRideSetting('maximum_bidding_fare_driver', 0).toDouble();
    if (maxBid > 0 && fare > maxBid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Max bid allowed is ₹${maxBid.toStringAsFixed(0)}')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unauthorized')),
        );
        return;
      }

      final selectedTimeMinutes = _selectedTimeMinutes();
      final selectedTimeText = _selectedTimeText();
      print('INTERCITY_SELECTED_TIME $selectedTimeText');
      print('INTERCITY_SELECTED_TIME_MINUTES $selectedTimeMinutes');
      print('INTERCITY_BID_AMOUNT $fare');

      final vehicleType = await _sessionService.getVehicleType();
      final vehicleColor = await _sessionService.getVehicleColor();
      final vehicleNumber = await _sessionService.getVehicleNumber();

      print('===== SESSION VEHICLE DATA =====');
      print('SESSION VEHICLE TYPE = $vehicleType');
      print('SESSION VEHICLE COLOR = $vehicleColor');
      print('SESSION VEHICLE NUMBER = $vehicleNumber');
      print('================================');

      final resp = await const ApiService().sendIntercityBid(
        token: token,
        rideId: rideId,
        price: fare,
        timeMinutes: selectedTimeMinutes,
        vehicleType: vehicleType.isNotEmpty ? vehicleType : widget.ride.vehicleType,
        vehicleColor: vehicleColor,
        vehicleNumber: vehicleNumber,
        vehicleName: vehicleType.isNotEmpty ? vehicleType : '', // Use vehicle_type as vehicle_name for now
        arrivalTime: selectedTimeText,
      );

      print('INTERCITY_BID_SENT $resp');

      if (!mounted) return;
      final ok = resp['success'] == true;
      if (!ok) {
        final msg = (resp['message'] ?? 'Failed to send bid').toString();
        if (isWalletInsufficientMessage(msg)) {
          await showWalletInsufficientDialog(context, message: msg);
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showTimePicker() {
    final now = DateTime.now();
    final initial = DateTime(now.year, now.month, now.day, selectedHour, selectedMinute);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            height: 300,
            padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                    const Expanded(
                      child: Text(
                        'Select Time',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Select', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    initialDateTime: initial,
                    onDateTimeChanged: (DateTime newDateTime) {
                      setState(() {
                        selectedHour = newDateTime.hour;
                        selectedMinute = newDateTime.minute;
                        period = selectedHour >= 12 ? 'PM' : 'AM';
                        if (selectedHour > 12) selectedHour -= 12;
                        if (selectedHour == 0) selectedHour = 12;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final pickup = ride.pickup.trim().isEmpty ? '-' : ride.pickup.trim();
    final drop = ride.drop.trim().isEmpty ? '-' : ride.drop.trim();
    final timeText = _selectedTimeText();

    final name = _driverName.trim().isEmpty ? 'Driver' : _driverName.trim();
    final hasImg = _driverImage.startsWith('http://') || _driverImage.startsWith('https://');

    final sheet = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(25),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: hasImg ? NetworkImage(_driverImage) : null,
                      child: !hasImg ? const Icon(Icons.person, color: Colors.grey) : null,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(
                          '★ ${(_driverRating <= 0 ? 0.0 : _driverRating).toStringAsFixed(1)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).colorScheme.surface),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pickup, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      Text(drop, style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      onPressed: _loading ? null : () => _setFare(_fare - 10),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE9E9E9)),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      child: const Text('-10', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    Text(
                      '₹${_money(_fare)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                    ElevatedButton(
                      onPressed: _loading ? null : () => _setFare(_fare + 10),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      child: const Text('+10', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _fareCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final n = double.tryParse(val.trim()) ?? 0;
                    _fare = n;
                  },
                ),
                const SizedBox(height: 15),
                GestureDetector(
                  onTap: _showTimePicker,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).colorScheme.surface),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, color: Colors.black54),
                        const SizedBox(width: 10),
                        Text(timeText, style: const TextStyle(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: ViteLoader(strokeWidth: 2.2, color: Colors.white),
                          )
                        : Text(
                            'ACCEPT FARE ON ₹${_money(_fare)}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: sheet,
        ),
      ],
    );
  }
}


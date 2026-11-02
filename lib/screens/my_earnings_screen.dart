import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/screens/activity/trip_detail_screen.dart';
import 'package:vite_captain/screens/driver_history_screen.dart';

class MyEarningsScreen extends StatefulWidget {
  const MyEarningsScreen({super.key});

  @override
  State<MyEarningsScreen> createState() => _MyEarningsScreenState();
}

class _MyEarningsScreenState extends State<MyEarningsScreen> {
  static const _green = Color(0xFF009640);

  String _range = 'today';
  DateTime? _from;
  DateTime? _to;
  Map<String, dynamic> _data = <String, dynamic>{};
  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  bool _historyReady = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString()) ?? 0;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _money(dynamic v) {
    final n = _asDouble(v);
    if (n == 0) return '0';
    final fixed = n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
    return fixed;
  }

  IconData _vehicleIcon(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'truck') return Icons.local_shipping;
    if (v == 'bike') return Icons.two_wheeler;
    if (v == 'suv') return Icons.directions_car_filled;
    if (v == 'car') return Icons.directions_car;
    return Icons.local_taxi;
  }

  String _vehicleLabel(String raw) {
    final trimmed = raw.trim();
    final v = trimmed.toLowerCase();
    if (v == 'truck') return 'Parcel';
    if (v == 'bike') return 'Bike';
    if (v == 'car') return 'Car';
    if (v == 'suv') return 'SUV';
    if (trimmed.isNotEmpty) return trimmed;
    return 'Vehicle';
  }

  DateTime? _parseDay(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(s);
    } catch (_) {}
    return DateTime.tryParse(s);
  }

  bool _inRange(DateTime? day) {
    if (_range == 'all') return true;
    if (day == null) return false;
    final date = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();
    if (_range == 'today') {
      return date.year == now.year && date.month == now.month && date.day == now.day;
    }
    if (_range == 'month') return date.year == now.year && date.month == now.month;
    if (_range == 'year') return date.year == now.year;
    if (_range == 'custom') {
      if (_from == null || _to == null) return false;
      final start = DateTime(_from!.year, _from!.month, _from!.day);
      final end = DateTime(_to!.year, _to!.month, _to!.day);
      return !date.isBefore(start) && !date.isAfter(end);
    }
    return true;
  }

  List<Map<String, dynamic>> get _visibleRides {
    if (!_historyReady) return const <Map<String, dynamic>>[];
    if (_range == 'all') return _history;
    return _history.where((ride) => _inRange(_parseDay(ride['date']))).toList();
  }

  double _minutesOf(Map<String, dynamic> ride) {
    final match = RegExp(r'([0-9]*\.?[0-9]+)').firstMatch((ride['duration'] ?? '').toString());
    return match == null ? 0 : (double.tryParse(match.group(1)!) ?? 0);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _from != null && _to != null ? DateTimeRange(start: _from!, end: _to!) : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: _green, onPrimary: Colors.white),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
      _range = 'custom';
    });
  }

  Future<void> _load() async {
    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _data = <String, dynamic>{};
          _history = <Map<String, dynamic>>[];
          _historyReady = false;
        });
        return;
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      };
      final query = <String, String>{'range': _range};
      if (_range == 'custom' && _from != null && _to != null) {
        query['from'] = DateFormat('yyyy-MM-dd').format(_from!);
        query['to'] = DateFormat('yyyy-MM-dd').format(_to!);
      }
      final results = await Future.wait([
        DioClient.dio.get(
          Uri.parse('$baseUrl/driver-earnings').replace(queryParameters: query).toString(),
          options: Options(validateStatus: (_) => true, headers: headers),
        ),
        DioClient.dio.get(
          '$baseUrl/driver/history',
          options: Options(validateStatus: (_) => true, headers: headers),
        ),
      ]);

      dynamic earnings = results[0].data;
      if (earnings is String) earnings = jsonDecode(earnings);
      dynamic history = results[1].data;
      if (history is String) history = jsonDecode(history);
      final rows = history is Map && history['data'] is List ? history['data'] as List : const <dynamic>[];

      if (!mounted) return;
      setState(() {
        _data = earnings is Map<String, dynamic> ? earnings : <String, dynamic>{};
        _history = rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
        _historyReady = history is Map && history['status'] == true;
      });
    } catch (_) {}
  }

  BoxDecoration _cardDecoration({Color? color, Color? borderColor}) {
    return BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor ?? Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget _buildSmallCard(String title, String value) {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: _cardDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderColor: const Color(0xFFD1FAE5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, color: _green, fontSize: 16),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ok = _data['status'] == true;
    final latest = (ok ? _data['latest_ride'] : null);
    final latestRideFromApi = latest is Map ? Map<String, dynamic>.from(latest) : <String, dynamic>{};

    final visible = _visibleRides;
    final useHistory = _historyReady;
    double sumOf(String? type) {
      final Iterable<Map<String, dynamic>> rows = type == null
          ? visible
          : visible.where((ride) => (ride['type'] ?? '').toString() == type);
      return rows.fold<double>(0, (sum, ride) => sum + _asDouble(ride['amount']));
    }

    final summaryValue = useHistory
        ? sumOf(null)
        : (_range == 'all'
            ? _asDouble(ok ? _data['total_earning'] : 0)
            : _asDouble(ok ? (_data['scoped_earning'] ?? (_range == 'today' ? _data['today_earning'] : _data['total_earning'])) : 0));
    final totalEarning = summaryValue.toStringAsFixed(2);
    final totalTrips = useHistory
        ? visible.length
        : (_range == 'all' ? _asInt(ok ? _data['total_trips'] : 0) : _asInt(ok ? (_data['scoped_trips'] ?? _data['total_trips']) : 0));
    final totalMinutes = visible.fold<double>(0, (sum, ride) => sum + _minutesOf(ride));
    final totalHours = useHistory
        ? (totalMinutes <= 0 ? '0 Hrs' : '${(totalMinutes / 60).toStringAsFixed(totalMinutes < 60 ? 2 : 1)} Hrs')
        : _text(ok ? (_range == 'all' ? _data['total_hours'] : (_data['scoped_hours'] ?? _data['total_hours'])) : '0 Hrs');
    final avgPerTrip = totalTrips <= 0 ? '0.00' : (summaryValue / totalTrips).toStringAsFixed(2);
    final rideEarning = (useHistory ? sumOf('ride') : _asDouble(ok ? (_data['scoped_ride_earning'] ?? _data['ride_earning']) : 0)).toStringAsFixed(2);
    final parcelEarning = (useHistory ? sumOf('parcel') : _asDouble(ok ? (_data['scoped_parcel_earning'] ?? _data['parcel_earning']) : 0)).toStringAsFixed(2);
    final intercityEarning = (useHistory ? sumOf('intercity') : _asDouble(ok ? (_data['scoped_intercity_earning'] ?? _data['intercity_earning']) : 0)).toStringAsFixed(2);
    final latestRide = useHistory
        ? (visible.isEmpty
            ? <String, dynamic>{}
            : <String, dynamic>{
                'ride_id': visible.first['ride_id'],
                'pickup': visible.first['pickup'],
                'destination': visible.first['destination'],
                'amount': visible.first['amount'],
                'date_time': visible.first['date'],
                'distance': visible.first['distance'],
                'duration': visible.first['duration'],
                'vehicle_type': visible.first['vehicle_type'],
                'type': visible.first['type'],
              })
        : latestRideFromApi;

    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, topInset + 16, 16, 22),
            decoration: const BoxDecoration(
              color: Color(0xFF009640),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: const Text(
              'My Earnings',
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
        onRefresh: _load,
        color: _green,
        child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _rangeChip('Today', 'today'),
                          _rangeChip('This Month', 'month'),
                          _rangeChip('This Year', 'year'),
                          _rangeChip(_customLabel(), 'custom'),
                          _rangeChip('All', 'all'),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(),
                      child: Column(
                        children: [
                          Text('Total Earnings', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('₹ $totalEarning', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(child: _buildSmallCard('Trips', '$totalTrips')),
                              const SizedBox(width: 8),
                              Expanded(child: _buildSmallCard('Online', totalHours)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildSmallCard('Avg / Trip', '₹$avgPerTrip')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                    child: Text('Earnings Breakdown', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: _cardDecoration(),
                      child: Column(
                        children: [
                          _breakRow(Icons.local_taxi_outlined, 'Ride Earnings', '₹$rideEarning'),
                          _breakRow(Icons.inventory_2_outlined, 'Parcel Earnings', '₹$parcelEarning'),
                          _breakRow(Icons.alt_route, 'Intercity Earnings', '₹$intercityEarning'),
                          _breakRow(Icons.schedule, 'Online Hours', totalHours, last: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recommended Bookings',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DriverHistoryScreen()),
                          );
                        },
                        child: const Text('View All', style: TextStyle(color: _green, fontWeight: FontWeight.w900)),
                      ),
                    ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: latestRide.isEmpty
                    ? Container(
                      padding: const EdgeInsets.all(20),
                      decoration: _cardDecoration(),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined, color: Color(0xFF9CA3AF), size: 36),
                          SizedBox(height: 8),
                          Text('No transactions yet', style: TextStyle(fontWeight: FontWeight.w800)),
                          SizedBox(height: 4),
                          Text(
                            'Your earnings details will appear here once you complete rides.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  : GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TripDetailScreen(
                              trip: latestRide,
                              kind: (_text(latestRide['type']).toLowerCase() == 'parcel') ? 'parcel' : 'ride',
                            ),
                          ),
                        );
                      },
                      child: _latestRideCard(latestRide),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _customLabel() {
    if (_from == null || _to == null) return 'Custom Date';
    final fmt = DateFormat('dd MMM');
    return '${fmt.format(_from!)} - ${fmt.format(_to!)}';
  }

  Widget _rangeChip(String label, String value) {
    final selected = _range == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : _green,
          ),
        ),
        selected: selected,
        selectedColor: _green,
        backgroundColor: Theme.of(context).colorScheme.surface,
        side: BorderSide(color: selected ? _green : const Color(0xFFD1D5DB)),
        onSelected: (_) async {
          if (value == 'custom') {
            await _pickCustomRange();
            return;
          }
          if (_range == value) return;
          setState(() => _range = value);
        },
      ),
    );
  }

  Widget _breakRow(IconData icon, String label, String value, {bool last = false}) {
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: _green),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        if (!last) const Divider(height: 1),
      ],
    );
  }

  Widget _latestRideCard(Map<String, dynamic> ride) {
    final rideId = _text(ride['ride_id']);
    final pickup = _text(ride['pickup']);
    final destination = _text(ride['destination']);
    final amount = _money(ride['amount']);
    final dateTimeRaw = _text(ride['date_time']);
    final distance = _text(ride['distance']);
    final duration = _text(ride['duration']);
    final vehicleTypeRaw = _text(ride['vehicle_type']);
    final typeRaw = _text(ride['type']).toLowerCase();
    final isParcel = typeRaw == 'parcel';

    String dateChip = dateTimeRaw;
    try {
      if (dateTimeRaw.isNotEmpty) {
        final parsed = DateTime.tryParse(dateTimeRaw.replaceAll(' ', 'T'));
        if (parsed != null) {
          dateChip = DateFormat('dd MMM, hh:mm a').format(parsed);
        }
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD1FAE5)),
                ),
                child: Icon(isParcel ? Icons.local_shipping : _vehicleIcon(vehicleTypeRaw), color: _green),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rideId.isEmpty
                          ? (isParcel ? 'Parcel' : 'Trip')
                          : (isParcel ? 'Parcel #$rideId' : 'Trip #$rideId'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isParcel ? 'Parcel' : _vehicleLabel(vehicleTypeRaw),
                      style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  dateChip,
                  style: const TextStyle(color: _green, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(width: 10, height: 10, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                  Container(width: 2, height: 26, color: Colors.grey.shade300),
                  const Icon(Icons.location_on, size: 18, color: Colors.red),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pickup.isEmpty ? '-' : pickup, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text(destination.isEmpty ? '-' : destination, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Est: $duration  |  Dist: $distance',
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD1FAE5)),
                ),
                child: Text(
                  '₹$amount',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: _green),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }
}


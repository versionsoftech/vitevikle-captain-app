import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/screens/driver_history_screen.dart';

class MyEarningsScreen extends StatefulWidget {
  const MyEarningsScreen({super.key});

  @override
  State<MyEarningsScreen> createState() => _MyEarningsScreenState();
}

class _MyEarningsScreenState extends State<MyEarningsScreen> {
  static const _green = Color(0xFF00A651);
  static const double _topCardHeight = 108;

  bool _loading = true;
  Map<String, dynamic> _data = <String, dynamic>{};

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _data = <String, dynamic>{};
          _loading = false;
        });
        return;
      }

      final uri = Uri.parse('$baseUrl/driver-earnings');
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

      dynamic decoded = resp.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) throw Exception('Unexpected response');

      if (kDebugMode) {
        debugPrint('driver-earnings latest_ride => ${decoded['latest_ride']}');
      }

      if (!mounted) return;
      setState(() {
        _data = decoded;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = <String, dynamic>{};
        _loading = false;
      });
    }
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

  Widget _buildTopCard(String title, String value) {
    return Container(
      height: _topCardHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                value,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: _green),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallCard(String title, String value) {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: _cardDecoration(
        color: const Color(0xFFF6FFFA),
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
    final latestRide = latest is Map ? Map<String, dynamic>.from(latest) : <String, dynamic>{};

    final todayEarning = _money(ok ? _data['today_earning'] : 0);
    final todayTips = _money(ok ? _data['today_tips'] : 0);
    final todayHours = _text(ok ? _data['today_login_hours'] : '0 Hrs');

    final totalEarning = _money(ok ? _data['total_earning'] : 0);
    final totalTrips = _asInt(ok ? _data['total_trips'] : 0);
    final totalHours = _text(ok ? _data['total_hours'] : '0 Hrs');

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('My Earnings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _green,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildTopCard("Today's Earnings", '₹$todayEarning')),
                      const SizedBox(width: 10),
                      Expanded(child: _buildTopCard("Today's Tips", '₹$todayTips')),
                      const SizedBox(width: 10),
                      Expanded(child: _buildTopCard("Today's Login Hrs", todayHours)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text('Total Earnings', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            '₹$totalEarning',
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _green),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(child: _buildSmallCard('Total Trips', '$totalTrips')),
                            const SizedBox(width: 10),
                            Expanded(child: _buildSmallCard('Total Driving Hrs', totalHours)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Latest Booking',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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
                  if (latestRide.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(),
                      child: const Text('No rides yet', style: TextStyle(fontWeight: FontWeight.w700)),
                    )
                  else
                    _latestRideCard(latestRide),
                ],
              ),
      ),
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
                  color: const Color(0xFFF6FFFA),
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
                  color: const Color(0xFFE8F5E9),
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
                  color: const Color(0xFFF0FFF7),
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


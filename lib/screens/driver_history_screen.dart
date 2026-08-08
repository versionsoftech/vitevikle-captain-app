import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';

class DriverHistoryScreen extends StatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  State<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends State<DriverHistoryScreen> {
  static const _green = Color(0xFF00A651);

  bool _loading = true;
  List<Map<String, dynamic>> _rides = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
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
          _rides = <Map<String, dynamic>>[];
          _loading = false;
        });
        return;
      }

      final uri = Uri.parse('$baseUrl/driver/history');
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

      final ok = decoded['status'] == true;
      final data = decoded['data'];
      final next = <Map<String, dynamic>>[];
      if (ok && data is List) {
        for (final item in data) {
          if (item is Map) next.add(Map<String, dynamic>.from(item));
        }
      }

      if (!mounted) return;
      setState(() {
        _rides = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rides = <Map<String, dynamic>>[];
        _loading = false;
      });
    }
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse((v ?? '').toString()) ?? 0;
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
    final v = raw.trim().toLowerCase();
    if (v == 'truck') return 'Parcel';
    if (v == 'bike') return 'Bike';
    if (v == 'car') return 'Car';
    if (v == 'suv') return 'SUV';
    return 'Vehicle';
  }

  DateTime? _parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      final parts = s.split('/');
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) return DateTime(y, m, d);
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    final groupOrder = <String>[];

    for (final r in _rides) {
      final dt = _parseDate(_text(r['date']));
      final key = dt == null ? '' : DateFormat('EEEE, MMMM d, yyyy').format(dt);
      final k = key.isEmpty ? 'History' : key;
      grouped.putIfAbsent(k, () {
        groupOrder.add(k);
        return <Map<String, dynamic>>[];
      }).add(r);
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: _green,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rides.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 160),
                      Center(child: Text('No history found', style: TextStyle(fontWeight: FontWeight.w700))),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: groupOrder.length,
                    itemBuilder: (context, index) {
                      final key = groupOrder[index];
                      final items = grouped[key] ?? <Map<String, dynamic>>[];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
                            child: Text(
                              key.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.grey),
                            ),
                          ),
                          ...items.map(_rideCard),
                        ],
                      );
                    },
                  ),
      ),
    );
  }

  Widget _rideCard(Map<String, dynamic> ride) {
    final customer = _text(ride['customer_name']);
    final rideId = _text(ride['ride_id']);
    final date = _text(ride['date']);
    final pickup = _text(ride['pickup']);
    final destination = _text(ride['destination']);
    final vehicleTypeRaw = _text(ride['vehicle_type']);
    final typeRaw = _text(ride['type']).toLowerCase();
    final isParcel = typeRaw == 'parcel';
    final distance = _text(ride['distance']);
    final duration = _text(ride['duration']);
    final amount = _asDouble(ride['amount']);

    return Container(
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customer.isEmpty ? 'Customer' : customer, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        rideId.isEmpty ? 'ID' : 'ID #$rideId',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.grey),
                      ),
                    ],
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
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                    Container(width: 2, height: 28, color: Colors.grey.shade300),
                    const Icon(Icons.location_on, size: 18, color: Colors.red),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pickup, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      Text(destination, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
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
                Icon(isParcel ? Icons.local_shipping : _vehicleIcon(vehicleTypeRaw), size: 18, color: _green),
                const SizedBox(width: 6),
                Text(isParcel ? 'Parcel' : _vehicleLabel(vehicleTypeRaw), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 14),
                const Icon(Icons.route, size: 18, color: Colors.black87),
                const SizedBox(width: 6),
                Text(distance, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 14),
                const Icon(Icons.timer, size: 18, color: Colors.black87),
                const SizedBox(width: 6),
                Text(duration, style: const TextStyle(fontWeight: FontWeight.w800)),
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
                const Icon(Icons.account_balance_wallet, size: 18, color: _green),
                const SizedBox(width: 8),
                Text(
                  '₹${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)}',
                  style: const TextStyle(color: _green, fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


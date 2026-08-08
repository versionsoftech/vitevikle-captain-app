import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
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
      final driverId = ((await const SessionService().getDriverId()) ?? '').trim();
      if (driverId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _rides = <Map<String, dynamic>>[];
          _loading = false;
        });
        return;
      }

      final uri = Uri.parse('$baseUrl/completed-rides/$driverId');
      final resp = await DioClient.dio.get(
        uri.toString(),
        options: Options(
          validateStatus: (_) => true,
          headers: const {
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );

      dynamic decoded = resp.data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is! Map<String, dynamic>) throw Exception('Unexpected response');

      final ok = decoded['success'] == true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Activity'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rides.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 160),
                      Center(
                        child: Text(
                          'No completed rides',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rides.length,
                    itemBuilder: (context, index) {
                      final ride = _rides[index];
                      final rideId = (ride['rideId'] ?? ride['_id'] ?? '').toString();
                      final customerName = (ride['customerName'] ?? ride['userName'] ?? 'Customer').toString();
                      final amount = (ride['finalFare'] ?? ride['amount'] ?? ride['price'] ?? ride['fare'] ?? '').toString();
                      final status = (ride['status'] ?? ride['bookingStatus'] ?? 'Completed').toString();
                      final date = (ride['date'] ?? ride['createdAt'] ?? ride['updatedAt'] ?? '').toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rideId.isEmpty ? 'Ride' : 'Ride ID: $rideId',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              customerName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    amount.isEmpty ? '-' : 'â‚¹$amount',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                                  ),
                                ),
                                Text(
                                  status,
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.green),
                                ),
                              ],
                            ),
                            if (date.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                date,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}


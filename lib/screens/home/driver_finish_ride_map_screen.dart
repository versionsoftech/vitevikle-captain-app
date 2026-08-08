import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/location_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/screens/home/driver_payment_screen.dart';

class DriverFinishRideMapScreen extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic> ride;
  final String googleApiKey;

  const DriverFinishRideMapScreen({
    super.key,
    required this.rideId,
    required this.ride,
    required this.googleApiKey,
  });

  @override
  State<DriverFinishRideMapScreen> createState() => _DriverFinishRideMapScreenState();
}

class _DriverFinishRideMapScreenState extends State<DriverFinishRideMapScreen> {
  static const themeRed = Color(0xFFFF3B30);

  final LocationService _locationService = const LocationService();
  final PolylinePoints _polylinePoints = PolylinePoints();

  GoogleMapController? _map;
  StreamSubscription<Position>? _positionSub;
  Timer? _timer;

  LatLng? _driver;
  LatLng? _drop;
  LatLng? _pickup;

  int _elapsed = 0;
  bool _finishing = false;

  Set<Marker> _markers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};

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

  Future<void> _showCommissionSnackFromResponse(Map<String, dynamic> res) async {
    try {
      final commission = _asMap(res['commission']);
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

  double? _tryDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  LatLng? _parseLatLng(dynamic node) {
    if (node is! Map) return null;
    final lat = _tryDouble(node['lat'] ?? node['latitude']);
    final lng = _tryDouble(node['lng'] ?? node['lon'] ?? node['longitude']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  String _formatTimer(int seconds) {
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _fitBounds(LatLng a, LatLng b) async {
    final map = _map;
    if (map == null) return;
    final bounds = LatLngBounds(
      southwest: LatLng(min(a.latitude, b.latitude), min(a.longitude, b.longitude)),
      northeast: LatLng(max(a.latitude, b.latitude), max(a.longitude, b.longitude)),
    );
    try {
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } catch (_) {
      try {
        await map.animateCamera(CameraUpdate.newLatLngZoom(b, 16));
      } catch (_) {}
    }
  }

  Uri _buildDirectionsUri({
    required LatLng origin,
    required LatLng destination,
    required String apiKey,
  }) {
    return Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
        'key': apiKey,
      },
    );
  }

  Future<void> _loadRoute(LatLng origin, LatLng destination) async {
    final apiKey = widget.googleApiKey.trim();
    if (apiKey.isEmpty) return;

    try {
      final res = await DioClient.dio.get(
        _buildDirectionsUri(origin: origin, destination: destination, apiKey: apiKey).toString(),
      );

      dynamic raw = res.data;
      if (raw is String) raw = jsonDecode(raw);
      if (raw is! Map<String, dynamic>) return;

      final routes = (raw['routes'] as List<dynamic>? ?? []);
      if (routes.isEmpty) return;

      final route0 = routes.first;
      if (route0 is! Map) return;
      final overview = (route0['overview_polyline'] as Map?) ?? {};
      final encoded = (overview['points'] ?? '').toString();

      final decoded = encoded.isNotEmpty
          ? _polylinePoints.decodePolyline(encoded).map((p) => LatLng(p.latitude, p.longitude)).toList(growable: false)
          : <LatLng>[origin, destination];

      if (!mounted) return;
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: decoded,
            color: const Color(0xFF2F6BFF),
            width: 5,
            geodesic: true,
          ),
        };
      });
    } catch (_) {
      return;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed += 1;
      });
    });
  }

  Future<void> _startLocation() async {
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
    ).listen(
      (p) {
        if (!mounted) return;
        final next = LatLng(p.latitude, p.longitude);
        _driver = next;
        _syncMarkers();
      },
      onError: (_) {},
    );

    try {
      final p = await _locationService.getCurrentLocation();
      _driver = LatLng(p.latitude, p.longitude);
      _syncMarkers();
    } catch (_) {}
  }

  void _syncMarkers() {
    final driver = _driver;
    final drop = _drop;
    if (drop == null) return;

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('drop'),
          position: drop,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
        if (driver != null)
          Marker(
            markerId: const MarkerId('driver'),
            position: driver,
            anchor: const Offset(0.5, 0.5),
            flat: true,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ),
      };
    });
  }

  Future<void> _finishRide() async {
    if (_finishing) return;
    final rideId = widget.rideId.trim();
    if (rideId.isEmpty) return;

    setState(() {
      _finishing = true;
    });

    try {
      final driverId = (await const SessionService().getDriverId() ?? '').trim();
      final token = (await const SessionService().getToken() ?? '').trim();
      if (driverId.isEmpty) throw Exception('missing driver');
      final res = await const ApiService().completeRide(token: token, rideRequestId: rideId, driverId: driverId, isIntercity: false);
      await _showCommissionSnackFromResponse(res);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverPaymentScreen(ride: widget.ride),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Failed to finish ride')));
    } finally {
      if (mounted) {
        setState(() {
          _finishing = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _pickup = _parseLatLng(widget.ride['pickup']);
    _drop = _parseLatLng(widget.ride['drop']);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pickup = _pickup;
      final drop = _drop;
      if (pickup != null && drop != null) {
        await _loadRoute(pickup, drop);
        await _fitBounds(pickup, drop);
      }
    });

    _startTimer();
    _startLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _positionSub = null;
    _timer?.cancel();
    _timer = null;
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final pickupNode = ride['pickup'];
    final dropNode = ride['drop'];
    final pickupAddress = (ride['pickup_address'] ?? (pickupNode is Map ? pickupNode['address'] : null) ?? '').toString().trim();
    final dropAddress = (ride['drop_address'] ?? (dropNode is Map ? dropNode['address'] : null) ?? '').toString().trim();
    final fareValue = (ride['finalFare'] ?? ride['fare']);
    final fare = fareValue is num ? fareValue.round().toString() : (fareValue?.toString() ?? '').trim();

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _driver ?? _drop ?? const LatLng(20.5937, 78.9629),
                  zoom: 16,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: _markers,
                polylines: _polylines,
                onMapCreated: (c) {
                  _map = c;
                },
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 5))],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('End the ride', style: TextStyle(fontWeight: FontWeight.w900)),
                          Text(_formatTimer(_elapsed), style: const TextStyle(fontWeight: FontWeight.w900, color: themeRed)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, -2))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0xFFF1F5F9),
                              child: Icon(Icons.location_on_outlined, color: themeRed),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pickupAddress.isEmpty ? 'Pickup address' : pickupAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dropAddress.isEmpty ? 'Drop address' : dropAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(fare.isEmpty ? '' : '₹$fare', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                            Row(
                              children: [
                                IconButton(onPressed: () {}, icon: const Icon(Icons.call)),
                                IconButton(onPressed: () {}, icon: const Icon(Icons.message)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _finishing ? null : _finishRide,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: themeRed,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              _finishing ? 'Finishing...' : 'Finish the ride',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
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


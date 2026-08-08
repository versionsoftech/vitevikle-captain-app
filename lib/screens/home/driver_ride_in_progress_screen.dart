import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vite_captain/screens/activity/activity_screen.dart';
import 'package:vite_captain/screens/chat/ride_chat_screen.dart';
import 'package:vite_captain/screens/home/driver_payment_screen.dart';
import 'package:vite_captain/screens/home/home_map_screen.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/location_service.dart';
import 'package:vite_captain/services/session_service.dart';

class DriverRideInProgressScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  final String googleApiKey;

  const DriverRideInProgressScreen({
    super.key,
    required this.ride,
    required this.googleApiKey,
  });

  @override
  State<DriverRideInProgressScreen> createState() => _DriverRideInProgressScreenState();
}

class _DriverRideInProgressScreenState extends State<DriverRideInProgressScreen> {
  static const themeGreen = Color(0xFF22C55E);
  static const double _dropArrivedDistanceMeters = 30;

  final PolylinePoints _polylinePoints = PolylinePoints();
  final GlobalKey<SlideActionState> _endSlideKey = GlobalKey<SlideActionState>();

  GoogleMapController? _map;
  StreamSubscription<Position>? _positionSub;

  LatLng? _driverLatLng;
  LatLng? _dropLatLng;
  LatLng? _prevDriverLatLng;
  DateTime? _prevDriverAt;
  double _driverSpeedKmh = 0;

  bool _loading = true;
  bool _navFollowEnabled = true;
  bool _arrivedAtDrop = false;
  bool _handlingEndRide = false;
  bool _waitingForArrivalConfirmation = false;
  bool _arrivalWaitingDialogOpen = false;

  Timer? _rideStatusTimer;
  Map<String, dynamic>? _rideDetails;
  bool _navigatedToPayment = false;

  Timer? _timer;
  int _elapsedSeconds = 0;

  DateTime? _lastRouteRefreshAt;
  String? _distanceText;
  String? _durationText;

  Set<Marker> _markers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};
  List<LatLng> _routePoints = <LatLng>[];

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

  @override
  void initState() {
    super.initState();
    _dropLatLng = _parseLatLng(widget.ride['drop']);
    _startTimer();
    _startLiveLocation();
    _loadRideDetails();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _rideStatusTimer?.cancel();
    _rideStatusTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    try {
      _map?.dispose();
    } catch (_) {}
    _map = null;
    super.dispose();
  }

  Future<void> _loadRideDetails() async {
    final rideId = (widget.ride['_id'] ?? widget.ride['id'] ?? '').toString().trim();
    if (rideId.isEmpty) return;
    try {
      final res = await const ApiService().getRideDetails(rideId: rideId);
      if (!mounted) return;
      if (res['success'] != true) return;
      final data = res['data'];
      if (data is! Map) return;
      setState(() {
        _rideDetails = Map<String, dynamic>.from(data);
      });
    } catch (_) {
      return;
    }
  }

  void _startRideStatusPolling(String rideId) {
    _rideStatusTimer?.cancel();
    _rideStatusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final res = await const ApiService().getRideStatus(rideId: rideId);
        if (!mounted) return;
        final statusRaw = res['status'] ?? (res['data'] is Map ? (res['data']['status']) : null);
        final status = (statusRaw ?? '').toString().trim().toUpperCase();
        if (status == 'COMPLETED') {
          _rideStatusTimer?.cancel();
          _rideStatusTimer = null;
          if (_arrivalWaitingDialogOpen) {
            Navigator.of(context, rootNavigator: true).pop();
            _arrivalWaitingDialogOpen = false;
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverPaymentScreen(ride: {
                ...widget.ride,
                if (_rideDetails != null) ..._rideDetails!,
              }),
            ),
          );
        }

        if (status == 'CANCELLED' || status == 'CANCELED') {
          _rideStatusTimer?.cancel();
          _rideStatusTimer = null;
          if (_arrivalWaitingDialogOpen) {
            Navigator.of(context, rootNavigator: true).pop();
            _arrivalWaitingDialogOpen = false;
          }
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Ride cancelled by rider'),
              duration: Duration(seconds: 4),
              backgroundColor: Color(0xFFB91C1C),
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }

        if (status == 'IN_PROGRESS' || status == 'ONGOING' || status == 'STARTED') {
          _rideStatusTimer?.cancel();
          _rideStatusTimer = null;
          if (_arrivalWaitingDialogOpen) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          setState(() {
            _waitingForArrivalConfirmation = false;
          });
          return;
        }
      } catch (_) {
        return;
      }
    });
  }

  Future<void> _showArrivalWaitingDialog() async {
    if (_arrivalWaitingDialogOpen) return;
    if (!mounted) return;
    _arrivalWaitingDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return WillPopScope(
          onWillPop: () async => false,
          child: const AlertDialog(
            title: Text('Waiting for user confirmation'),
            content: Text('Please wait...'),
          ),
        );
      },
    ).whenComplete(() {
      _arrivalWaitingDialogOpen = false;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds += 1;
      });
    });
  }

  String _formatTimer(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
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

  void _startLiveLocation() {
    _positionSub?.cancel();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 3),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: 'Tracking ride in progress',
        notificationTitle: 'ViteWay Driver',
        enableWakeLock: true,
      ),
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) {
        if (!mounted) return;
        final next = LatLng(p.latitude, p.longitude);
        _handleDriverLocationUpdate(next, heading: p.heading, speedMps: p.speed);
      },
      onError: (_) {},
    );
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180.0;
    final lat2 = to.latitude * pi / 180.0;
    final dLng = (to.longitude - from.longitude) * pi / 180.0;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    final brng = atan2(y, x) * 180.0 / pi;
    return (brng + 360.0) % 360.0;
  }

  int _nearestRouteIndex(LatLng p, List<LatLng> pts) {
    if (pts.isEmpty) return 0;
    var bestI = 0;
    var bestD = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final q = pts[i];
      final d = (p.latitude - q.latitude) * (p.latitude - q.latitude) +
          (p.longitude - q.longitude) * (p.longitude - q.longitude);
      if (d < bestD) {
        bestD = d;
        bestI = i;
      }
    }
    return bestI;
  }

  double _turnSharpnessDeg(LatLng driver, List<LatLng> route) {
    if (route.length < 10) return 0;
    final idx = _nearestRouteIndex(driver, route);
    final i1 = idx.clamp(0, route.length - 1);
    final i2 = (idx + 4).clamp(0, route.length - 1);
    final i3 = (idx + 8).clamp(0, route.length - 1);
    if (i1 == i2 || i2 == i3) return 0;
    final b1 = _bearingBetween(route[i1], route[i2]);
    final b2 = _bearingBetween(route[i2], route[i3]);
    var diff = (b2 - b1).abs();
    if (diff > 180) diff = 360 - diff;
    return diff;
  }

  double _smartZoom({required double speedKmh, required double turnSharpnessDeg}) {
    if (turnSharpnessDeg >= 30) return 18;
    if (speedKmh > 40) return 14;
    if (speedKmh > 20) return 16;
    return 18;
  }

  LatLng _forwardOffset(LatLng p, {required double bearingDeg, double meters = 35}) {
    final brng = bearingDeg * pi / 180.0;
    final dLat = (meters * cos(brng)) / 111320.0;
    final dLng = (meters * sin(brng)) / (111320.0 * cos(p.latitude * pi / 180.0));
    return LatLng(p.latitude + dLat, p.longitude + dLng);
  }

  Uri _buildDirectionsUri({required LatLng origin, required LatLng destination, required String apiKey}) {
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
      final result = await _polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: apiKey,
        request: PolylineRequest(
          origin: PointLatLng(origin.latitude, origin.longitude),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.driving,
        ),
      );

      final decoded = (result.points.isNotEmpty)
          ? result.points.map((p) => LatLng(p.latitude, p.longitude)).toList(growable: false)
          : <LatLng>[origin, destination];

      if (!mounted) return;
      _routePoints = decoded;
      _updateSplitRoutePolylines(full: decoded, driver: origin);
    } catch (_) {}
  }

  void _updateSplitRoutePolylines({required List<LatLng> full, required LatLng driver}) {
    if (full.length < 2) return;
    final idx = _nearestRouteIndex(driver, full);
    final completed = full.sublist(0, (idx + 1).clamp(1, full.length));
    final remaining = full.sublist(idx.clamp(0, full.length - 1));

    setState(() {
      _polylines = {
        if (completed.length >= 2)
          Polyline(
            polylineId: const PolylineId('completed_route'),
            points: completed,
            color: const Color(0xFFBDBDBD),
            width: 6,
          ),
        if (remaining.length >= 2)
          Polyline(
            polylineId: const PolylineId('remaining_route'),
            points: remaining,
            color: const Color(0xFF1E88E5),
            width: 6,
          ),
      };
    });
  }

  Future<void> _openGoogleNavigation(LatLng destination) async {
    final navUrl = Uri.parse('google.navigation:q=${destination.latitude},${destination.longitude}&mode=d');
    final webUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving',
    );

    try {
      final ok = await canLaunchUrl(navUrl);
      if (ok) {
        await launchUrl(navUrl, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    try {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _handleDriverLocationUpdate(LatLng driver, {double? heading, double? speedMps}) async {
    final drop = _dropLatLng;
    if (drop == null) return;

    if (_loading) {
      _loading = false;
    }

    final now = DateTime.now();
    final prevAt = _prevDriverAt;
    final prev = _prevDriverLatLng;
    if (prev != null && prevAt != null) {
      final dt = now.difference(prevAt).inMilliseconds / 1000.0;
      if (dt > 0) {
        final meters = Geolocator.distanceBetween(prev.latitude, prev.longitude, driver.latitude, driver.longitude);
        _driverSpeedKmh = (meters / dt) * 3.6;
      }
    }
    if (speedMps != null && speedMps > 0) {
      _driverSpeedKmh = speedMps * 3.6;
    }
    _prevDriverAt = now;
    _prevDriverLatLng = driver;

    final distanceToDrop = Geolocator.distanceBetween(
      driver.latitude,
      driver.longitude,
      drop.latitude,
      drop.longitude,
    );

    setState(() {
      _driverLatLng = driver;
      _markers = {
        Marker(
          markerId: const MarkerId('drop'),
          position: drop,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
        Marker(
          markerId: const MarkerId('driver'),
          position: driver,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      };
    });

    final route = _routePoints;
    if (route.isNotEmpty) {
      _updateSplitRoutePolylines(full: route, driver: driver);
    }

    try {
      if (_navFollowEnabled) {
        final computedBearing = heading ?? (prev == null ? 0.0 : _bearingBetween(prev, driver));
        final turn = route.isNotEmpty ? _turnSharpnessDeg(driver, route) : 0.0;
        final zoom = _smartZoom(speedKmh: _driverSpeedKmh, turnSharpnessDeg: turn);
        final target = _forwardOffset(driver, bearingDeg: computedBearing);
        await _map?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: target,
              zoom: zoom,
              tilt: 45,
              bearing: computedBearing,
            ),
          ),
        );
      } else {
        await _map?.animateCamera(CameraUpdate.newLatLng(driver));
      }
    } catch (_) {}

    if (!_arrivedAtDrop && distanceToDrop <= _dropArrivedDistanceMeters) {
      _arrivedAtDrop = true;
      await _handleEndRide();
    }

    final now2 = DateTime.now();
    final last = _lastRouteRefreshAt;
    final hasRoute = _routePoints.length >= 2;
    var needFetch = !hasRoute;
    if (hasRoute) {
      final idx = _nearestRouteIndex(driver, _routePoints);
      final nearest = _routePoints[idx.clamp(0, _routePoints.length - 1)];
      final offRoute = Geolocator.distanceBetween(
        driver.latitude,
        driver.longitude,
        nearest.latitude,
        nearest.longitude,
      );
      final canRefetch = last == null || now2.difference(last).inSeconds >= 90;
      needFetch = offRoute > 120 && canRefetch;
    }
    if (needFetch) {
      _lastRouteRefreshAt = now2;
      await _loadRoute(driver, drop);
    }
  }

  Future<bool> _handleEndRide() async {
    if (_handlingEndRide) return false;
    if (_waitingForArrivalConfirmation) return false;
    final rideId = (widget.ride['_id'] ?? widget.ride['id'] ?? '').toString().trim();
    if (rideId.isEmpty) return false;

    _handlingEndRide = true;
    try {
      _positionSub?.cancel();
      _positionSub = null;
    } catch (_) {
      if (mounted) {
        setState(() {
          _handlingEndRide = false;
        });
      } else {
        _handlingEndRide = false;
      }
      return false;
    }

    try {
      final driverId = (await const SessionService().getDriverId() ?? '').trim();
      if (driverId.isEmpty) {
        if (!mounted) {
          _handlingEndRide = false;
          return false;
        }
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(const SnackBar(content: Text('Missing driver info')));
        setState(() {
          _handlingEndRide = false;
        });
        return false;
      }

      final token = (await const SessionService().getToken() ?? '').trim();
      final res = await const ApiService().completeRide(
        token: token,
        rideRequestId: rideId,
        driverId: driverId,
        isIntercity: false,
      );

      await _showCommissionSnackFromResponse(res is Map<String, dynamic> ? res : <String, dynamic>{});

      if (!mounted) {
        _handlingEndRide = false;
        return false;
      }

      final apiStatusRaw = res['status'] ?? (res['ride'] is Map ? (res['ride']['status']) : null);
      final apiStatus = (apiStatusRaw ?? '').toString().trim().toUpperCase();
      final ok = (res['success'] == true) || apiStatus == 'COMPLETED' || ((res['message'] ?? '').toString().toLowerCase().contains('success'));
      if (!ok) {
        final msg = (res['message'] ?? 'Failed to complete ride').toString();
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(content: Text(msg)));
        setState(() {
          _handlingEndRide = false;
        });
        return false;
      }

      final rideNode = res['ride'];
      final data = rideNode is Map ? Map<String, dynamic>.from(rideNode) : <String, dynamic>{};

      setState(() {
        _handlingEndRide = false;
        _waitingForArrivalConfirmation = false;
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverPaymentScreen(ride: {
            ...widget.ride,
            ...data,
          }),
        ),
      );
      return true;
    } catch (_) {
      if (!mounted) {
        _handlingEndRide = false;
        return false;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Failed to complete ride')));
      setState(() {
        _handlingEndRide = false;
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driverLatLng;
    final drop = _dropLatLng;

    final details = _rideDetails ?? const {};
    final userNode = widget.ride['user'];
    final userMap = userNode is Map ? userNode : const {};
    final riderId = (userMap['_id'] ?? userMap['id'] ?? widget.ride['userId'] ?? widget.ride['user_id'] ?? '').toString().trim();
    final riderPhone = (details['user_mobile'] ?? details['user_phone'] ?? userMap['mobile'] ?? userMap['phone'] ?? widget.ride['userMobile'] ?? widget.ride['mobile'] ?? widget.ride['phone'] ?? '')
        .toString()
        .trim();
    final riderName = (details['user_name'] ?? userMap['name'] ?? widget.ride['customerName'] ?? widget.ride['userName'] ?? widget.ride['name'] ?? 'Customer')
        .toString()
        .trim();

    final userImageUrl = (details['user_image'] ?? widget.ride['user_image'] ?? widget.ride['userImage'] ?? (userMap['profile_image'] ?? '') ?? '')
        .toString()
        .trim();
    final hasUserImage = userImageUrl.startsWith('http://') || userImageUrl.startsWith('https://');

    final dropNode = widget.ride['drop'];
    final dropAddress = (widget.ride['drop_address'] ?? (dropNode is Map ? dropNode['address'] : null) ?? 'Drop location')
        .toString()
        .trim();

    final fareValue = details['fare'] ?? widget.ride['fare'];
    final fare = fareValue is num ? fareValue.round() : int.tryParse(fareValue?.toString() ?? '') ?? 0;

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
                  target: driver ?? drop ?? const LatLng(20.5937, 78.9629),
                  zoom: 16,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: _markers,
                polylines: _polylines,
                onMapCreated: (controller) {
                  _map = controller;
                },
              ),
            Positioned(
              top: 40,
              left: 10,
              right: 10,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 6)),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('End the ride', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text("Please don't be late", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                      Text(
                        _formatTimer(_elapsedSeconds),
                        style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if ((_distanceText ?? '').trim().isNotEmpty || (_durationText ?? '').trim().isNotEmpty)
              Positioned(
                top: 110,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 6)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((_distanceText ?? '').trim().isNotEmpty)
                        Text(_distanceText!.trim(), style: const TextStyle(fontWeight: FontWeight.w900)),
                      if ((_durationText ?? '').trim().isNotEmpty)
                        Text(_durationText!.trim(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 20,
              bottom: 220,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (drop == null) return;
                  _openGoogleNavigation(drop);
                },
                icon: const Icon(Icons.navigation),
                label: const Text('Navigate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, -6)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFF1D4ED8),
                          foregroundColor: Colors.white,
                          child: hasUserImage
                              ? ClipOval(
                                  child: Image.network(
                                    userImageUrl,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(Icons.person, color: Colors.white, size: 22);
                                    },
                                  ),
                                )
                              : const Icon(Icons.person, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(riderName.isEmpty ? 'Customer' : riderName, style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(dropAddress, style: const TextStyle(color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('₹$fare', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () async {
                                final p = riderPhone.trim();
                                if (p.isEmpty) return;
                                final Uri uri = Uri(scheme: 'tel', path: p);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                              icon: const Icon(Icons.call),
                            ),
                            IconButton(
                              onPressed: () async {
                                final receiverId = riderId.trim();
                                if (receiverId.isEmpty) return;
                                final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
                                if (!mounted || driverId.isEmpty) return;
                                final rideId = (widget.ride['_id'] ?? widget.ride['id'] ?? '').toString().trim();
                                if (rideId.isEmpty) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RideChatScreen(
                                      rideId: rideId,
                                      senderId: driverId,
                                      receiverId: receiverId,
                                      senderRole: 'driver',
                                      title: riderName.isEmpty ? 'Chat' : riderName,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.message),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: SlideAction(
                            key: _endSlideKey,
                            height: 54,
                            outerColor: Colors.transparent,
                            innerColor: Colors.white,
                            sliderButtonIcon: const Icon(Icons.directions_bike, color: Color(0xFFEF4444)),
                            text: 'Swipe To End Ride',
                            textStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            borderRadius: 30,
                            onSubmit: () async {
                              if (_handlingEndRide || _waitingForArrivalConfirmation) return;
                              final ok = await _handleEndRide();
                              if (!ok) {
                                if (mounted) {
                                  print('SLIDE_RESET_CALLED: Resetting end ride slide action');
                                  _endSlideKey.currentState?.reset();
                                  print('SLIDE_RESET_COMPLETED: End ride slide action reset completed');
                                } else {
                                  print('SLIDE_RESET_SKIPPED: Widget not mounted, skipping reset');
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const Positioned(
                top: 16,
                right: 16,
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


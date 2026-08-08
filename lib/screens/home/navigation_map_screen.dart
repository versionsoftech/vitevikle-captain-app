import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/location_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/chat_notification_provider.dart';
import 'package:vite_captain/screens/home/driver_finish_ride_map_screen.dart';
import 'package:vite_captain/screens/home/driver_ride_in_progress_screen.dart';

class NavigationMapScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  final String googleApiKey;

  const NavigationMapScreen({
    super.key,
    required this.ride,
    required this.googleApiKey,
  });

  @override
  State<NavigationMapScreen> createState() => _NavigationMapScreenState();
}

class _NavigationMapScreenState extends State<NavigationMapScreen> {
  static const themeGreen = Color(0xFF22C55E);
  static const sosRed = Color(0xFFEF4444);
  static const double _arrivedDistanceMeters = 200;
  static const int _arrivedEtaMinutes = 2;
  static const double _dropArrivedDistanceMeters = 30;

  final LocationService _locationService = const LocationService();
  final PolylinePoints _polylinePoints = PolylinePoints();

  GoogleMapController? _map;
  LatLng? _driverLatLng;
  LatLng? _pickupLatLng;
  LatLng? _dropLatLng;
  bool _rideStarted = false;
  String _rideStatus = '';
  bool _navFollowEnabled = false;
  Timer? _navStartTimer;
  bool _arrivedAtDrop = false;
  bool _completingRide = false;

  StreamSubscription<Position>? _positionSub;
  Timer? _timer;
  Timer? _routeTimer;
  Timer? _sosTimer;

  io.Socket? _socket;
  DateTime? _lastSocketEmitAt;

  int _elapsedSeconds = 0;
  String? _distanceText;
  String? _durationText;

  bool _loading = true;
  bool _arrivedPopupShown = false;
  bool _otpSheetShown = false;
  bool _callingArrivedApi = false;
  bool _verifyingOtp = false;
  DateTime? _lastRouteRefreshAt;
  bool _sosActive = false;
  String _sosAlertId = '';

  Set<Marker> _markers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};
  List<LatLng> _routePoints = <LatLng>[];

  LatLng? _prevDriverLatLng;
  DateTime? _prevDriverAt;
  double _driverSpeedKmh = 0;

  List<LatLng> _rideStopsLatLngs() {
    final raw = widget.ride['stops'] ?? widget.ride['Stops'] ?? widget.ride['stop'] ?? widget.ride['waypoints'];
    if (raw is! List) return const <LatLng>[];
    final out = <LatLng>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final latRaw = m['latitude'] ?? m['lat'];
      final lngRaw = m['longitude'] ?? m['lng'];
      final lat = latRaw is num ? latRaw.toDouble() : double.tryParse((latRaw ?? '').toString());
      final lng = lngRaw is num ? lngRaw.toDouble() : double.tryParse((lngRaw ?? '').toString());
      if (lat == null || lng == null) continue;
      out.add(LatLng(lat, lng));
    }
    return out;
  }

  Future<void> _openGoogleNavigation(LatLng destination, {List<LatLng> waypoints = const <LatLng>[]}) async {
    final navUrl = Uri.parse(
      'google.navigation:q=${destination.latitude},${destination.longitude}&mode=d',
    );
    final wp = waypoints
        .map((p) => '${p.latitude},${p.longitude}')
        .join('|');
    final webUrl = Uri.parse(
      waypoints.isEmpty
          ? 'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving'
          : 'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving&waypoints=$wp',
    );

    try {
      if (waypoints.isEmpty) {
        final ok = await canLaunchUrl(navUrl);
        if (ok) {
          await launchUrl(navUrl, mode: LaunchMode.externalApplication);
          return;
        }
      }
    } catch (_) {}

    try {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } catch (_) {}
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

  int? _parseEtaMinutes(String? text) {
    final raw = (text ?? '').toString().trim().toLowerCase();
    if (raw.isEmpty) return null;

    final match = RegExp(r'(\d+)').firstMatch(raw);
    if (match == null) return null;
    final n = int.tryParse(match.group(1) ?? '');
    if (n == null) return null;

    if (raw.contains('hour')) return n * 60;
    if (raw.contains('min')) return n;
    return n;
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

  void _startLiveLocation() {
    _positionSub?.cancel();

    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'Tracking ride in progress',
          notificationTitle: 'ViteWay Driver',
          enableWakeLock: true,
        ),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      );
    }

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
    if (route.length < 8) return 0;
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

  void _updateSplitRoutePolylines({
    required List<LatLng> full,
    required LatLng driver,
  }) {
    if (full.length < 2) return;
    final idx = _nearestRouteIndex(driver, full);
    final completed = idx <= 1 ? <LatLng>[] : full.sublist(0, idx + 1);
    final remaining = idx >= full.length - 2 ? <LatLng>[] : full.sublist(idx, full.length);

    setState(() {
      final others = _polylines
          .where((p) => p.polylineId.value != 'completed_route' && p.polylineId.value != 'remaining_route')
          .toSet();
      final nextPolys = <Polyline>{...others};
      if (completed.length >= 2) {
        nextPolys.add(
          Polyline(
            polylineId: const PolylineId('completed_route'),
            points: completed,
            color: const Color(0xFFBDBDBD),
            width: 6,
            geodesic: true,
          ),
        );
      }
      if (remaining.length >= 2) {
        nextPolys.add(
          Polyline(
            polylineId: const PolylineId('remaining_route'),
            points: remaining,
            color: const Color(0xFF1E88E5),
            width: 6,
            geodesic: true,
          ),
        );
      }
      _polylines = nextPolys;
    });
  }

  void _ensureSocketConnected() {
    if (_socket != null) return;
    try {
      final socket = io.io(
        'https://adm.vitevikle.com',
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': true,
          'reconnection': true,
        },
      );
      _socket = socket;
      socket.connect();
    } catch (_) {
      return;
    }
  }

  void _emitDriverSocketUpdate({
    required String rideId,
    required LatLng driver,
    required double? heading,
  }) {
    final socket = _socket;
    if (socket == null) return;
    if (!socket.connected) return;

    final now = DateTime.now();
    final last = _lastSocketEmitAt;
    if (last != null && now.difference(last).inMilliseconds < 2800) {
      return;
    }
    _lastSocketEmitAt = now;

    socket.emit('driverLocationUpdate', {
      'rideId': rideId,
      'lat': driver.latitude,
      'lng': driver.longitude,
      'heading': heading,
    });
  }

  Future<void> _handleDriverLocationUpdate(LatLng driver, {double? heading, double? speedMps}) async {
    final rideId = (widget.ride['_id'] ?? widget.ride['id'] ?? '').toString().trim();
    if (rideId.isNotEmpty) {
      _ensureSocketConnected();
      _emitDriverSocketUpdate(rideId: rideId, driver: driver, heading: heading);
    }

    final destination = _rideStarted ? _dropLatLng : _pickupLatLng;
    if (destination == null) {
      setState(() {
        _driverLatLng = driver;
      });
      return;
    }

    final distance = Geolocator.distanceBetween(
      driver.latitude,
      driver.longitude,
      destination.latitude,
      destination.longitude,
    );

    final etaMinutes = _parseEtaMinutes(_durationText);
    print('Distance: $distance');
    print('ETA: ${etaMinutes ?? -1}');

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

    setState(() {
      _driverLatLng = driver;
      _markers = {
        Marker(
          markerId: MarkerId(_rideStarted ? 'drop' : 'pickup'),
          position: destination,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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

    if (_rideStarted) {
      if (!_arrivedAtDrop && distance <= _dropArrivedDistanceMeters) {
        _arrivedAtDrop = true;
        await _handleArrivedAtDrop();
      }
    } else {
      final shouldArrive = distance <= _arrivedDistanceMeters || (etaMinutes != null && etaMinutes <= _arrivedEtaMinutes);
      if (shouldArrive && !_arrivedPopupShown) {
        _arrivedPopupShown = true;
        _showArrivedPopup();
      }
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
      await _loadRoute(driver, destination);
    }
  }

  Future<void> _bringAppToFront() async {
    if (!Platform.isAndroid) return;
    try {
      final pkg = (await PackageInfo.fromPlatform()).packageName;
      if (pkg.trim().isEmpty) return;
      final intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.LAUNCHER',
        package: pkg,
        flags: <int>[268435456, 67108864],
      );
      await intent.launch();
    } catch (_) {
      return;
    }
  }

  Future<void> _handleArrivedAtDrop() async {
    if (_completingRide) return;
    final rideId = (widget.ride['_id'] ?? widget.ride['id'] ?? '').toString().trim();
    if (rideId.isEmpty) return;

    _completingRide = true;
    try {
      _positionSub?.cancel();
      _positionSub = null;
    } catch (_) {
      return;
    } finally {
      _completingRide = false;
    }

    await _bringAppToFront();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => DriverFinishRideMapScreen(
          rideId: rideId,
          ride: widget.ride,
          googleApiKey: widget.googleApiKey,
        ),
      ),
      (route) => false,
    );
  }

  void _showArrivedPopup() {
    final pickupNode = widget.ride['pickup'];
    final pickupAddress = (widget.ride['pickup_address'] ?? (pickupNode is Map ? pickupNode['address'] : null) ?? '')
        .toString()
        .trim();

    final userNode = widget.ride['user'];
    final userMap = userNode is Map ? userNode : const {};
    final riderName = (userMap['name'] ?? widget.ride['customerName'] ?? widget.ride['userName'] ?? widget.ride['name'] ?? 'Customer')
        .toString()
        .trim();
    final ratingValue = widget.ride['rating'];
    final ratingText = ratingValue is num
        ? ratingValue.toStringAsFixed(1)
        : (double.tryParse(ratingValue?.toString() ?? '')?.toStringAsFixed(1) ?? '4.5');
    final fareValue = widget.ride['fare'];
    final fare = fareValue is num ? fareValue.round() : int.tryParse(fareValue?.toString() ?? '') ?? 0;

    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: false,
      enableDrag: false,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: _ArrivedBottomSheet(
            pickupAddress: pickupAddress,
            riderName: riderName.isEmpty ? 'Customer' : riderName,
            ratingText: ratingText,
            fare: fare,
            onImHere: () {
              _handleImHere();
            },
            onCancel: () {
              Navigator.pop(context);
            },
          ),
        );
      },
    );
  }

  Future<void> _handleImHere() async {
    if (_callingArrivedApi) return;

    final rideId = (widget.ride['_id'] ?? widget.ride['id'] ?? '').toString().trim();
    final driverId = (await const SessionService().getDriverId() ?? '').trim();
    if (rideId.isEmpty || driverId.isEmpty) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Missing ride/driver info')));
      return;
    }

    _callingArrivedApi = true;
    try {
      final res = await const ApiService().driverArrived(
        rideId: rideId,
        driverId: driverId,
      );

      if (!mounted) return;
      final ok = (res['success'] == true) || ((res['message'] ?? '').toString().toLowerCase().contains('success'));
      if (!ok) {
        final msg = (res['message'] ?? 'Failed to update arrival').toString();
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      try {
        _ensureSocketConnected();
        final s = _socket;
        if (s != null && s.connected) {
          s.emit('driver_arrived', {
            'rideId': rideId,
          });
        }
      } catch (_) {}

      Navigator.pop(context);
      if (_otpSheetShown) return;
      _otpSheetShown = true;
      _showOtpSheet(rideId: rideId);
    } catch (_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Network error. Please try again.')));
    } finally {
      _callingArrivedApi = false;
    }
  }

  void _showOtpSheet({
    required String rideId,
  }) {
    final pickupNode = widget.ride['pickup'];
    final pickupAddress = (widget.ride['pickup_address'] ?? (pickupNode is Map ? pickupNode['address'] : null) ?? '')
        .toString()
        .trim();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: _OtpBottomSheet(
            rideId: rideId,
            pickupAddress: pickupAddress,
            pickupLatLng: _pickupLatLng,
            driverLatLng: _driverLatLng,
            dropLatLng: _parseLatLng(widget.ride['drop']),
            onRideStarted: () async {
              await _onRideStarted();
            },
            onCancel: () {
              Navigator.pop(context);
            },
            onVerify: (otp) async {
              if (_verifyingOtp) return false;
              _verifyingOtp = true;
              try {
                // Debug
                // ignore: avoid_print
                print('OTP Entered: $otp');
                final res = await const ApiService().verifyRideOtp(
                  rideId: rideId,
                  otp: otp,
                );
                // Debug
                // ignore: avoid_print
                print('API Response (verifyRideOtp): $res');
                final ok = res['success'] == true;
                if (!mounted) return ok;
                if (!ok) {
                  final msg = (res['message'] ?? 'Invalid OTP').toString();
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  messenger?.hideCurrentSnackBar();
                  messenger?.showSnackBar(SnackBar(content: Text(msg)));
                  return false;
                }
                if (mounted) {
                  setState(() {
                    _rideStatus = 'ONGOING';
                    try {
                      widget.ride['status'] = 'ongoing';
                    } catch (_) {}
                  });
                }
                return true;
              } catch (_) {
                if (!mounted) return false;
                final messenger = ScaffoldMessenger.maybeOf(context);
                messenger?.hideCurrentSnackBar();
                messenger?.showSnackBar(const SnackBar(content: Text('Network error. Please try again.')));
                return false;
              } finally {
                _verifyingOtp = false;
              }
            },
          ),
        );
      },
    ).whenComplete(() {
      _otpSheetShown = false;
    });
  }

  Future<void> _onRideStarted() async {
    if (_callingArrivedApi) return;

    final rideId = (widget.ride['_id'] ?? widget.ride['id'] ?? '').toString().trim();
    final driverId = (await const SessionService().getDriverId() ?? '').trim();
    if (rideId.isEmpty || driverId.isEmpty) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Missing ride/driver info')));
      return;
    }

    _callingArrivedApi = true;
    try {
      final res = await const ApiService().startRide(
        rideRequestId: rideId,
        driverId: driverId,
      );

      if (!mounted) return;
      final ok = (res['success'] == true) || ((res['message'] ?? '').toString().toLowerCase().contains('success'));
      if (!ok) {
        final msg = (res['message'] ?? 'Failed to start ride').toString();
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      if (mounted) {
        setState(() {
          _rideStarted = true;
          _rideStatus = 'ONGOING';
        });
      }

      if (!mounted) return;

      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => DriverRideInProgressScreen(
              ride: widget.ride,
              googleApiKey: widget.googleApiKey,
            ),
          ),
          (route) => false,
        );
      });
    } catch (_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Network error. Please try again.')));
    } finally {
      _callingArrivedApi = false;
    }
  }

  LatLng? _parseLatLng(dynamic node) {
    if (node is! Map) return null;
    final lat = _tryDouble(node['lat'] ?? node['latitude']);
    final lng = _tryDouble(node['lng'] ?? node['lon'] ?? node['longitude']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
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

  Future<void> _fitBounds(LatLng a, LatLng b) async {
    final map = _map;
    if (map == null) return;

    final bounds = LatLngBounds(
      southwest: LatLng(min(a.latitude, b.latitude), min(a.longitude, b.longitude)),
      northeast: LatLng(max(a.latitude, b.latitude), max(a.longitude, b.longitude)),
    );

    try {
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
    } catch (_) {
      try {
        await map.animateCamera(CameraUpdate.newLatLngZoom(a, 14));
      } catch (_) {}
    }
  }

  Future<void> _loadRoute(LatLng origin, LatLng destination) async {
    final apiKey = widget.googleApiKey.trim();
    if (apiKey.isEmpty) return;

    try {
      final res = await DioClient.dio.get(
        _buildDirectionsUri(
          origin: origin,
          destination: destination,
          apiKey: apiKey,
        ).toString(),
      );

      dynamic raw = res.data;
      if (raw is String) raw = jsonDecode(raw);
      final data = raw as Map<String, dynamic>;
      final routes = (data['routes'] as List<dynamic>? ?? []);
      if (routes.isEmpty) return;

      final route0 = routes.first as Map<String, dynamic>;
      final overview = (route0['overview_polyline'] as Map<String, dynamic>?) ?? {};
      final encoded = (overview['points'] as String?) ?? '';
      if (encoded.isEmpty) return;

      final decoded = _polylinePoints
          .decodePolyline(encoded)
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList(growable: false);

      final legs = (route0['legs'] as List<dynamic>? ?? []);
      String? distance;
      String? duration;
      if (legs.isNotEmpty) {
        final leg0 = legs.first as Map<String, dynamic>;
        distance = (leg0['distance'] as Map<String, dynamic>?)?['text']?.toString();
        duration = (leg0['duration'] as Map<String, dynamic>?)?['text']?.toString();
      }

      if (!mounted) return;
      setState(() {
        _distanceText = distance;
        _durationText = duration;
        _routePoints = decoded.isNotEmpty ? decoded : [origin, destination];
      });

      final driver = _driverLatLng;
      if (driver != null && _routePoints.isNotEmpty) {
        _updateSplitRoutePolylines(full: _routePoints, driver: driver);
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
      });
    } catch (_) {}

    final pickup = _parseLatLng(widget.ride['pickup']);
    final drop = _parseLatLng(widget.ride['drop']);
    if (pickup == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      return;
    }

    final statusRaw = (widget.ride['status'] ?? '').toString().trim().toLowerCase();
    if (statusRaw == 'ongoing' || statusRaw == 'started') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => DriverRideInProgressScreen(
            ride: widget.ride,
            googleApiKey: widget.googleApiKey,
          ),
        ),
        (route) => false,
      );
      return;
    }

    LatLng? driver;
    try {
      final Position p = await _locationService.getCurrentLocation();
      driver = LatLng(p.latitude, p.longitude);
    } catch (_) {
      driver = null;
    }

    if (!mounted) return;
    setState(() {
      _pickupLatLng = pickup;
      _dropLatLng = drop;
      _driverLatLng = driver;
      _markers = {
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
        if (driver != null)
          Marker(
            markerId: const MarkerId('driver'),
            position: driver,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ),
      };
    });

    if (driver != null) {
      await _loadRoute(driver, pickup);
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
    });

    if (driver != null && _map != null) {
      await _fitBounds(driver, pickup);
    } else if (_map != null) {
      try {
        await _map!.animateCamera(CameraUpdate.newLatLngZoom(pickup, 15));
      } catch (_) {}
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
    _startTimer();
    _startLiveLocation();
    _startCancelPolling();
  }

  Timer? _cancelPollTimer;
  bool _handlingUserCancel = false;

  String get _navRideId =>
      (widget.ride['_id'] ?? widget.ride['id'] ?? '').toString().trim();

  void _startCancelPolling() {
    _cancelPollTimer?.cancel();
    _cancelPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollForUserCancel();
    });
    _pollForUserCancel();
  }

  Future<void> _pollForUserCancel() async {
    if (!mounted || _handlingUserCancel || _completingRide) return;
    final rideId = _navRideId;
    if (rideId.isEmpty) return;
    try {
      final res = await const ApiService().getRideStatus(rideId: rideId);
      if (!mounted || _handlingUserCancel) return;
      final dataNode = res['data'];
      final status = (res['status'] ??
              (dataNode is Map ? dataNode['status'] : null) ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      if (status == 'cancelled' || status == 'canceled') {
        _handlingUserCancel = true;
        _cancelPollTimer?.cancel();
        _cancelPollTimer = null;
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
      }
    } catch (_) {
      return;
    }
  }

  @override
  void dispose() {
    _cancelPollTimer?.cancel();
    _cancelPollTimer = null;
    _navStartTimer?.cancel();
    _navStartTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _timer?.cancel();
    _timer = null;
    _routeTimer?.cancel();
    _routeTimer = null;
    _sosTimer?.cancel();
    _sosTimer = null;
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _map?.dispose();
    super.dispose();
  }

  Future<void> _confirmAndTriggerSOS() async {
    if (_sosActive) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Emergency SOS'),
        content: const Text('Are you sure you want to send an emergency alert?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send SOS')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final driverId = (await const SessionService().getDriverId() ?? '').trim();
      if (driverId.isEmpty) return;

      final rideId = (widget.ride['_id'] ?? widget.ride['ride_id'] ?? widget.ride['booking_id'] ?? '').toString();
      final passengerName = (widget.ride['user_name'] ?? widget.ride['customerName'] ?? widget.ride['userName'] ?? '').toString();
      final vehicleNumber = (widget.ride['vehicle_number'] ?? widget.ride['vehicleNumber'] ?? '').toString();

      final pos = await _locationService.getCurrentLocation();
      final payload = {
        'ride_id': rideId,
        'passenger_name': passengerName,
        'vehicle_number': vehicleNumber,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'device_model': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown'),
        'app_version': (await PackageInfo.fromPlatform()).version,
      };

      if (!mounted) return;
      setState(() => _sosActive = true);

      final token = (await const SessionService().getToken() ?? '').trim();
      print('SOS_TOKEN $token');
      print('SOS_AUTH_HEADER Bearer $token');

      final resp = await const ApiService().triggerSOS(token: token, driverId: driverId, payload: payload);
      print('SOS_API_RESPONSE $resp');
      final ok = resp['success'] == true;
      if (!ok) {
        if (!mounted) return;
        setState(() => _sosActive = false);
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(content: Text((resp['message'] ?? 'Failed to send SOS').toString())));
        return;
      }
      _sosAlertId = (resp['alert_id'] ?? '').toString();

      // Get emergency contact phone from response or profile
      String emergencyPhone = '';
      if (resp['emergency_contact'] != null && resp['emergency_contact']['phone'] != null) {
        emergencyPhone = resp['emergency_contact']['phone'].toString().trim();
      } else {
        // Fallback to profile
        try {
          final token = (await const SessionService().getToken() ?? '').trim();
          if (token.isNotEmpty) {
            final prof = await const ApiService().getDriverProfile(token: token);
            final data = prof['data'];
            final ec = data is Map ? data['emergency_contact'] : null;
            emergencyPhone = ec is Map ? (ec['phone'] ?? '').toString().trim() : '';
          }
        } catch (_) {}
      }

      print('SOS_EMERGENCY_PHONE $emergencyPhone');

      // Automatically launch phone dialer
      if (emergencyPhone.isNotEmpty) {
        print('SOS_PHONE_DIAL_OPENED');
        print('SOS_PHONE_NUMBER $emergencyPhone');
        final uri = Uri(scheme: 'tel', path: emergencyPhone);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('SOS_DIALER_LAUNCHED $launched');
      } else {
        print('SOS_NO_EMERGENCY_PHONE');
      }

      _sosTimer?.cancel();
      _sosTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (!_sosActive || _sosAlertId.isEmpty) return;
        try {
          final p = await _locationService.getCurrentLocation();
          await const ApiService().trackSOS(
            alertId: _sosAlertId,
            lat: p.latitude,
            lng: p.longitude,
            speed: p.speed,
            direction: p.heading,
          );
        } catch (_) {}
      });

      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('SOS Alert Sent Successfully'), backgroundColor: Colors.redAccent));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sosActive = false);
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(const SnackBar(content: Text('Failed to send SOS')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickupLatLng = _pickupLatLng;

    final showBadge = (_distanceText != null && _distanceText!.isNotEmpty) ||
        (_durationText != null && _durationText!.isNotEmpty);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_rideStarted ? 'Trip in progress' : 'Going to Pickup'),
        backgroundColor: themeGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.22)),
                ),
                child: Text(
                  _formatTimer(_elapsedSeconds),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: pickupLatLng ?? const LatLng(20.5937, 78.9629),
                zoom: 13,
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
            if (showBadge)
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 6)),
                    ],
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_distanceText != null && _distanceText!.isNotEmpty)
                        Text(_distanceText!, style: const TextStyle(fontWeight: FontWeight.w900)),
                      if (_durationText != null && _durationText!.isNotEmpty)
                        Text(_durationText!, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'navigate_google',
                    backgroundColor: themeGreen,
                    foregroundColor: Colors.white,
                    onPressed: () {
                      final destination = _rideStarted ? _dropLatLng : _pickupLatLng;
                      if (destination == null) return;
                      final wps = _rideStarted ? _rideStopsLatLngs() : const <LatLng>[];
                      _openGoogleNavigation(destination, waypoints: wps);
                    },
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Navigate', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.extended(
                    heroTag: 'sos_button',
                    backgroundColor: sosRed,
                    foregroundColor: Colors.white,
                    onPressed: _confirmAndTriggerSOS,
                    icon: const Icon(Icons.emergency_share_rounded),
                    label: const Text('SOS', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.extended(
                    heroTag: 'manual_arrived',
                    backgroundColor: Colors.white,
                    foregroundColor: themeGreen,
                    onPressed: () {
                      if (_arrivedPopupShown) return;
                      _arrivedPopupShown = true;
                      _showArrivedPopup();
                    },
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('I have arrived', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton(
                    heroTag: 'recenter',
                    backgroundColor: themeGreen,
                    onPressed: () async {
                      final d = _driverLatLng;
                      final p = _pickupLatLng;
                      if (d == null || p == null) return;
                      await _fitBounds(d, p);
                    },
                    child: const Icon(Icons.my_location, color: Colors.white),
                  ),
                ],
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
    );
  }
}

class _OtpBottomSheet extends StatefulWidget {
  final String rideId;
  final String pickupAddress;
  final LatLng? pickupLatLng;
  final LatLng? driverLatLng;
  final LatLng? dropLatLng;
  final VoidCallback onRideStarted;
  final VoidCallback onCancel;
  final Future<bool> Function(String otp) onVerify;

  const _OtpBottomSheet({
    required this.rideId,
    required this.pickupAddress,
    required this.pickupLatLng,
    required this.driverLatLng,
    required this.dropLatLng,
    required this.onRideStarted,
    required this.onCancel,
    required this.onVerify,
  });

  @override
  State<_OtpBottomSheet> createState() => _OtpBottomSheetState();
}

class _OtpBottomSheetState extends State<_OtpBottomSheet> {
  static const themeGreen = Color(0xFF22C55E);
  static const lightGreen = Color(0xFFDCFCE7);
  static const uberRed = Color(0xFFFF3B30);

  final List<TextEditingController> _controllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  final GlobalKey<SlideActionState> _slideKey = GlobalKey<SlideActionState>();

  bool _submitting = false;
  bool _rideStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String _otp() {
    return _controllers.map((c) => c.text.trim()).join();
  }

  bool get _isOtpComplete {
    final val = _otp();
    return val.length == 4 && RegExp(r'^\d{4}$').hasMatch(val);
  }

  Future<void> startRide() async {
    final ok = await _submit();
    if (!ok) {
      if (mounted) {
        setState(() {
          _rideStarted = false;
        });
      } else {
        _rideStarted = false;
      }
      return;
    }

    try {
      widget.onRideStarted();
    } catch (_) {}
  }

  Future<bool> _submit() async {
    if (_submitting) return false;
    final otp = _otp();
    if (otp.length != 4) return false;

    setState(() {
      _submitting = true;
    });
    try {
      final ok = await widget.onVerify(otp);
      // Debug
      // ignore: avoid_print
      print('OTP Verify Result: $ok');
      if (!mounted) return false;
      if (!ok) {
        setState(() {
          _submitting = false;
        });
        _focusNodes.first.requestFocus();
        return false;
      }
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
      return true;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _submitting = false;
      });
      return false;
    }
  }

  void _onChanged(int index, String value) {
    final v = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (v != value) {
      _controllers[index].text = v;
      _controllers[index].selection = TextSelection.fromPosition(TextPosition(offset: v.length));
    }
    if (v.isEmpty) return;
    if (index < 3) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
    }
  }

  void _onBackspace(int index, RawKeyEvent e) {
    if (e is! RawKeyDownEvent) return;
    if (e.logicalKey != LogicalKeyboardKey.backspace) return;
    if (_controllers[index].text.isNotEmpty) return;
    if (index == 0) return;
    _focusNodes[index - 1].requestFocus();
    _controllers[index - 1].selection = TextSelection.fromPosition(
      TextPosition(offset: _controllers[index - 1].text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final pickup = widget.pickupAddress.trim().isEmpty ? 'Pick up' : widget.pickupAddress.trim();

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, -6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              height: 5,
              width: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              "Type your 'icebreaker' given by your customer to start your ride!",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(4, (i) {
              return SizedBox(
                width: 72,
                height: 60,
                child: RawKeyboardListener(
                  focusNode: FocusNode(skipTraversal: true),
                  onKey: (e) => _onBackspace(i, e),
                  child: TextField(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    enableInteractiveSelection: false,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
                    onChanged: (v) => _onChanged(i, v),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: themeGreen, width: 2.2),
                      ),
                    ),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.green, Colors.greenAccent],
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: _rideStarted
                    ? Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: themeGreen,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Center(
                          child: Icon(Icons.check, color: Colors.white, size: 28),
                        ),
                      )
                    : SlideAction(
                        key: _slideKey,
                        height: 56,
                        outerColor: Colors.transparent,
                        innerColor: Colors.white,
                        sliderButtonIcon: const Icon(Icons.arrow_forward, color: themeGreen),
                        text: 'Swipe to Start Ride',
                        textStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                        borderRadius: 30,
                        onSubmit: _submitting
                            ? null
                            : () async {
                                if (!_isOtpComplete) {
                                  if (mounted) {
                                    print('SLIDE_RESET_CALLED: Resetting navigation slide action');
                                    _slideKey.currentState?.reset();
                                    print('SLIDE_RESET_COMPLETED: Navigation slide action reset completed');
                                  } else {
                                    print('SLIDE_RESET_SKIPPED: Widget not mounted, skipping reset');
                                  }
                                  return;
                                }

                                if (mounted) {
                                  setState(() {
                                    _rideStarted = true;
                                  });
                                } else {
                                  _rideStarted = true;
                                }

                                await startRide();
                              },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: themeGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pick up', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(
                        pickup,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF334155), fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: _submitting
                      ? null
                      : () {
                          final messenger = ScaffoldMessenger.maybeOf(context);
                          messenger?.hideCurrentSnackBar();
                          messenger?.showSnackBar(const SnackBar(content: Text('Chat')));
                        },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Icon(Icons.chat_bubble_outline, color: themeGreen, size: 20),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: _submitting
                      ? null
                      : () {
                          final messenger = ScaffoldMessenger.maybeOf(context);
                          messenger?.hideCurrentSnackBar();
                          messenger?.showSnackBar(const SnackBar(content: Text('Call')));
                        },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Icon(Icons.call_outlined, color: themeGreen, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _submitting ? null : widget.onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE53935),
                side: const BorderSide(color: Color(0xFFE53935)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrivedBottomSheet extends StatelessWidget {
  final String pickupAddress;
  final String riderName;
  final String ratingText;
  final int fare;
  final VoidCallback onImHere;
  final VoidCallback onCancel;

  const _ArrivedBottomSheet({
    required this.pickupAddress,
    required this.riderName,
    required this.ratingText,
    required this.fare,
    required this.onImHere,
    required this.onCancel,
  });

  Widget _circleAction(BuildContext context, IconData icon, String label) {
    const themeGreen = Color(0xFF22C55E);

    return InkWell(
      onTap: () {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(content: Text(label)));
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: label.toLowerCase() == 'message'
            ? Consumer<ChatNotificationProvider>(
                builder: (context, n, _) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(child: Icon(icon, color: themeGreen, size: 20)),
                      if (n.unreadCount > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${n.unreadCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              )
            : Icon(icon, color: themeGreen, size: 20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const themeGreen = Color(0xFF22C55E);

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: Opacity(opacity: t.clamp(0, 1), child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, -6)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                height: 5,
                width: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  height: 10,
                  width: 10,
                  decoration: const BoxDecoration(color: themeGreen, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'You have arrived',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pickupAddress.trim().isEmpty ? 'Pickup location' : pickupAddress.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withOpacity(0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    messenger?.hideCurrentSnackBar();
                    messenger?.showSnackBar(const SnackBar(content: Text('Navigation')));
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: themeGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.navigation, color: themeGreen, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    riderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, size: 16, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text(
                        ratingText,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (fare > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: themeGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '₹$fare',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: themeGreen),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _circleAction(context, Icons.call_outlined, 'Call'),
                const SizedBox(width: 10),
                _circleAction(context, Icons.message_outlined, 'Message'),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onImHere,
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  "I'm Here",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935),
                  side: const BorderSide(color: Color(0xFFE53935)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


import 'dart:async';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vite_captain/maps/mappls_routes.dart';
import 'package:vite_captain/maps/mappls_geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vite_captain/maps/mappls_map.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/screens/parcel/parcel_payment_screen.dart';

class ParcelDropMapScreen extends StatefulWidget {
  const ParcelDropMapScreen({super.key, required this.parcel});

  final Map<String, dynamic> parcel;

  @override
  State<ParcelDropMapScreen> createState() => _ParcelDropMapScreenState();
}

class _ParcelDropMapScreenState extends State<ParcelDropMapScreen> {
  static const Color _green = Color(0xFF009640);


  MapplsViewController? _map;
  bool _loading = true;
  bool _completing = false;

  StreamSubscription<Position>? _posSub;
  io.Socket? _socket;
  DateTime? _lastEmitAt;
  DateTime? _lastRouteAt;

  LatLng? _driverLatLng;
  LatLng? _dropLatLng;

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

  Future<void> _showCommissionSnackFromResponse(Map<String, dynamic> resp) async {
    try {
      final raw = _asMap(resp['raw']);
      final commission = _asMap(raw['commission']);
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

  String _asTrimmed(dynamic v) => v == null ? '' : v.toString().trim();

  LatLng? _parseLatLng(dynamic node) {
    if (node is Map) {
      final lat = node['lat'] ?? node['latitude'];
      final lng = node['lng'] ?? node['lon'] ?? node['longitude'];
      final dLat = lat is num ? lat.toDouble() : double.tryParse(_asTrimmed(lat));
      final dLng = lng is num ? lng.toDouble() : double.tryParse(_asTrimmed(lng));
      if (dLat != null && dLng != null) {
        return LatLng(dLat, dLng);
      }
    }
    return null;
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    final a = address.trim();
    if (a.isEmpty) return null;
    try {
      final places = await locationFromAddress(a);
      if (places.isEmpty) return null;
      return LatLng(places.first.latitude, places.first.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMapData() async {
    final p = widget.parcel;

    LatLng? driverLatLng;
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      driverLatLng = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      driverLatLng = null;
    }

    final dropNode = p['drop'];
    final dropLatLng = _parseLatLng(dropNode) ?? _parseLatLng(p['drop_location']);
    final dropAddress = dropNode is Map ? _asTrimmed(dropNode['address']) : _asTrimmed(dropNode);

    LatLng? resolvedDrop = dropLatLng;
    if (resolvedDrop == null && dropAddress.isNotEmpty) {
      resolvedDrop = await _geocodeAddress(dropAddress);
    }

    if (!mounted) return;

    _driverLatLng = driverLatLng;
    _dropLatLng = resolvedDrop;

    _markers = <Marker>{
      if (_driverLatLng != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'You'),
        ),
      if (_dropLatLng != null)
        Marker(
          markerId: const MarkerId('drop'),
          position: _dropLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Drop'),
        ),
    };

    if (_driverLatLng != null && _dropLatLng != null) {
      await _loadRoute(_driverLatLng!, _dropLatLng!);
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
    });

    await _fitBounds();

    _ensureSocketConnected();
    _startDriverLocationStream();
  }

  void _ensureSocketConnected() {
    if (_socket != null) return;
    try {
      final socket = io.io(
        baseUrl.replaceAll('/api', ''),
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': true,
          'reconnection': true,
        },
      );
      _socket = socket;
      socket.connect();
    } catch (_) {
      _socket = null;
    }
  }

  void _emitDriverLocation({
    required LatLng driver,
    required String rideId,
    required String driverId,
  }) {
    final socket = _socket;
    if (socket == null) return;
    if (!socket.connected) return;

    final now = DateTime.now();
    final last = _lastEmitAt;
    if (last != null && now.difference(last).inMilliseconds < 2500) return;
    _lastEmitAt = now;

    socket.emit('driver_location_update', {
      'rideId': rideId,
      'ride_id': rideId,
      'driver_id': driverId,
      'lat': driver.latitude,
      'lng': driver.longitude,
    });

    socket.emit('driverLocationUpdate', {
      'rideId': rideId,
      'driver_id': driverId,
      'lat': driver.latitude,
      'lng': driver.longitude,
    });
  }

  void _startDriverLocationStream() {
    if (_posSub != null) return;
    final rideId = _asTrimmed(widget.parcel['_id'] ?? widget.parcel['id']);
    if (rideId.isEmpty) return;

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((pos) async {
      final next = LatLng(pos.latitude, pos.longitude);
      _driverLatLng = next;

      final drop = _dropLatLng;
      _markers = <Marker>{
        Marker(
          markerId: const MarkerId('driver'),
          position: next,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'You'),
        ),
        if (drop != null)
          Marker(
            markerId: const MarkerId('drop'),
            position: drop,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Drop'),
          ),
      };

      if (mounted) {
        setState(() {});
      }

      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (driverId.isNotEmpty) {
        _emitDriverLocation(driver: next, rideId: rideId, driverId: driverId);
      }

      if (drop != null) {
        final now = DateTime.now();
        final last = _lastRouteAt;
        final hasRoute = _routePoints.length >= 2;
        var needFetch = !hasRoute;
        if (hasRoute) {
          var bestD = double.infinity;
          for (final q in _routePoints) {
            final d = Geolocator.distanceBetween(next.latitude, next.longitude, q.latitude, q.longitude);
            if (d < bestD) bestD = d;
          }
          final canRefetch = last == null || now.difference(last).inSeconds >= 90;
          needFetch = bestD > 120 && canRefetch;
        }
        if (needFetch) {
          _lastRouteAt = now;
          await _loadRoute(next, drop);
        }
      }
    });
  }

  Future<void> _fitBounds() async {
    final map = _map;
    final a = _driverLatLng;
    final b = _dropLatLng;
    if (map == null || a == null || b == null) return;

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
    try {
      final route = await fetchMapplsRoute(origin, destination);
      if (route == null) return;

      if (!mounted) return;
      setState(() {
        _distanceText = route.distanceText;
        _durationText = route.durationText;
        _routePoints = route.points;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('driver_to_drop'),
            points: _routePoints,
            color: Theme.of(context).colorScheme.onSurface,
            width: 4,
          ),
        };
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _completeRide() async {
    if (_completing) return;

    final parcelId = _asTrimmed(widget.parcel['_id'] ?? widget.parcel['id']);
    if (parcelId.isEmpty) return;

    final paymentType = _asTrimmed(widget.parcel['payment_type'] ?? widget.parcel['paymentType'] ?? 'COD');
    final isWallet = paymentType.toLowerCase() == 'wallet';

    if (isWallet) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ParcelPaymentScreen(parcel: widget.parcel),
        ),
      );
      return;
    }

    setState(() => _completing = true);
    try {
      final token = (await const SessionService().getToken())?.trim() ?? '';
      if (token.isEmpty) return;

      final resp = await const ApiService().completeParcelRide(
        token: token,
        parcelId: parcelId,
      );

      await _showCommissionSnackFromResponse(resp is Map<String, dynamic> ? resp : <String, dynamic>{});

      if (!mounted) return;
      final ok = resp['success'] == true || resp['status'] == true || resp['success'] == 'true' || resp['status'] == 'true';
      if (!ok) {
        final rawMsg = (resp['message'] ?? 'Failed to complete ride').toString();
        final msg = rawMsg.toLowerCase().contains('unable to complete ride') ? 'Failed to complete ride' : rawMsg;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ride Completed âœ…'),
          backgroundColor: const Color(0xFF009640),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMapData();
    });
  }

  @override
  void dispose() {
    try {
      _posSub?.cancel();
    } catch (_) {}
    _posSub = null;
    try {
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driverLatLng;
    final init = driver ?? const LatLng(20.5937, 78.9629);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Drop Navigation'),
      ),
      body: Stack(
        children: [
          MapplsView(
            initialCameraPosition: CameraPosition(target: init, zoom: 12),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (c) async {
              _map = c;
              await _fitBounds();
            },
          ),
          if (_distanceText != null || _durationText != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _distanceText ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      _durationText ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _completing ? null : _completeRide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _completing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: ViteLoader(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('COMPLETE RIDE', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ),
          if (_loading)
            Container(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.75),
              child: const Center(child: ViteLoader(color: _green)),
            ),
        ],
      ),
    );
  }
}


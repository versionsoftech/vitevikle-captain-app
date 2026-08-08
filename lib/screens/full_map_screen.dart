import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:vite_captain/services/dio_client.dart';

class FullMapScreen extends StatefulWidget {
  final LatLng pickupLatLng;
  final LatLng destinationLatLng;
  final String? apiKey;

  const FullMapScreen({
    super.key,
    required this.pickupLatLng,
    required this.destinationLatLng,
    this.apiKey,
  });

  @override
  State<FullMapScreen> createState() => _FullMapScreenState();
}

class _FullMapScreenState extends State<FullMapScreen> {
  static const themeGreen = Color(0xFF1FB354);

  final PolylinePoints _polylinePoints = PolylinePoints();
  GoogleMapController? _map;

  bool _loadingRoute = true;
  String? _distanceText;
  String? _durationText;

  late Set<Marker> _markers;
  late Set<Polyline> _polylines;

  @override
  void initState() {
    super.initState();
    _markers = _buildMarkers();
    _polylines = <Polyline>{_buildFallbackPolyline()};
    _loadRoute();
  }

  Set<Marker> _buildMarkers() {
    return {
      Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickupLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destinationLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    };
  }

  Polyline _buildFallbackPolyline() {
    return Polyline(
      polylineId: const PolylineId('route'),
      points: [widget.pickupLatLng, widget.destinationLatLng],
      color: themeGreen,
      width: 5,
      geodesic: true,
    );
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

  Future<void> _loadRoute() async {
    final apiKey = widget.apiKey;
    if (apiKey == null || apiKey.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _loadingRoute = false;
      });
      return;
    }

    try {
      final res = await DioClient.dio.get(
        _buildDirectionsUri(
          origin: widget.pickupLatLng,
          destination: widget.destinationLatLng,
          apiKey: apiKey,
        ).toString(),
      );

      dynamic raw = res.data;
      if (raw is String) {
        raw = jsonDecode(raw);
      }

      final data = raw as Map<String, dynamic>;
      final routes = (data['routes'] as List<dynamic>? ?? []);
      if (routes.isEmpty) {
        throw Exception('NO_ROUTES');
      }

      final route0 = routes.first as Map<String, dynamic>;
      final overview = (route0['overview_polyline'] as Map<String, dynamic>?) ?? {};
      final encoded = (overview['points'] as String?) ?? '';
      if (encoded.isEmpty) {
        throw Exception('NO_POLYLINE');
      }

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
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: decoded.isNotEmpty
                ? decoded
                : [widget.pickupLatLng, widget.destinationLatLng],
            color: themeGreen,
            width: 5,
            geodesic: true,
          ),
        };
        _loadingRoute = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _polylines = <Polyline>{_buildFallbackPolyline()};
        _loadingRoute = false;
      });
    }
  }

  LatLngBounds _buildBounds() {
    return LatLngBounds(
      southwest: LatLng(
        min(widget.pickupLatLng.latitude, widget.destinationLatLng.latitude),
        min(widget.pickupLatLng.longitude, widget.destinationLatLng.longitude),
      ),
      northeast: LatLng(
        max(widget.pickupLatLng.latitude, widget.destinationLatLng.latitude),
        max(widget.pickupLatLng.longitude, widget.destinationLatLng.longitude),
      ),
    );
  }

  Future<void> _fitBounds() async {
    final map = _map;
    if (map == null) return;
    try {
      await map.animateCamera(CameraUpdate.newLatLngBounds(_buildBounds(), 60));
    } catch (_) {}
  }

  Widget _buildRouteInfoCard() {
    final distance = _distanceText;
    final duration = _durationText;
    if ((distance == null || distance.isEmpty) &&
        (duration == null || duration.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: themeGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.route, color: themeGreen, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  distance ?? '',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  duration ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Route'),
        backgroundColor: themeGreen,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: widget.pickupLatLng, zoom: 13),
            markers: _markers,
            polylines: _polylines,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _map = controller;
              Future.delayed(const Duration(milliseconds: 400), _fitBounds);
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: _buildRouteInfoCard(),
            ),
          ),
          if (_loadingRoute)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.white.withOpacity(0.15),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(themeGreen),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


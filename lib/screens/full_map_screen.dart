import 'dart:math';
import 'package:vite_captain/widgets/vite_loader.dart';

import 'package:flutter/material.dart';
import 'package:vite_captain/maps/mappls_map.dart';
import 'package:vite_captain/maps/mappls_routes.dart';

class FullMapScreen extends StatefulWidget {
  final LatLng pickupLatLng;
  final LatLng destinationLatLng;

  const FullMapScreen({
    super.key,
    required this.pickupLatLng,
    required this.destinationLatLng,
  });

  @override
  State<FullMapScreen> createState() => _FullMapScreenState();
}

class _FullMapScreenState extends State<FullMapScreen> {
  static const themeGreen = Color(0xFF1FB354);

  MapplsViewController? _map;

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

  Future<void> _loadRoute() async {
    try {
      final route = await fetchMapplsRoute(widget.pickupLatLng, widget.destinationLatLng);
      if (route == null) {
        throw Exception('NO_ROUTES');
      }

      if (!mounted) return;
      setState(() {
        _distanceText = route.distanceText;
        _durationText = route.durationText;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: route.points,
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
        color: Theme.of(context).colorScheme.surface,
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
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
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
          MapplsView(
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
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.15),
                  alignment: Alignment.center,
                  child: const ViteLoader(
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


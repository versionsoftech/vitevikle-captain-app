import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vite_captain/maps/mappls_map.dart';
import 'package:vite_captain/maps/mappls_routes.dart';
import 'package:vite_captain/maps/open_mappls_navigation.dart';
import 'package:vite_captain/models/intercity_request.dart';

class IntercityRideMapScreen extends StatefulWidget {
  final IntercityRequestModel ride;

  const IntercityRideMapScreen({
    super.key,
    required this.ride,
  });

  @override
  State<IntercityRideMapScreen> createState() => _IntercityRideMapScreenState();
}

class _IntercityRideMapScreenState extends State<IntercityRideMapScreen> {
  MapplsViewController? _map;

  late final LatLng _pickup;
  late final LatLng _drop;

  late final Set<Marker> _markers;
  Set<Polyline> _routes = <Polyline>{};

  @override
  void initState() {
    super.initState();
    _pickup = LatLng(widget.ride.pickupLat, widget.ride.pickupLng);
    _drop = LatLng(widget.ride.dropLat, widget.ride.dropLng);

    _markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: _pickup,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ),
      Marker(
        markerId: const MarkerId('drop'),
        position: _drop,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Drop'),
      ),
    };
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    final route = await fetchMapplsRoute(_pickup, _drop);
    if (!mounted) return;
    setState(() {
      _routes = <Polyline>{
        Polyline(
          polylineId: const PolylineId('intercity_route'),
          points: route?.points ?? <LatLng>[_pickup, _drop],
          color: const Color(0xFF009640),
          width: 5,
        ),
      };
    });
  }

  Future<void> _fitBounds() async {
    final map = _map;
    if (map == null) return;

    final bounds = LatLngBounds(
      southwest: LatLng(min(_pickup.latitude, _drop.latitude), min(_pickup.longitude, _drop.longitude)),
      northeast: LatLng(max(_pickup.latitude, _drop.latitude), max(_pickup.longitude, _drop.longitude)),
    );

    await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.ride.riderName.trim().isEmpty ? 'User' : widget.ride.riderName.trim();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF009640),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        title: Text(name),
      ),
      body: Stack(
        children: [
          MapplsView(
            initialCameraPosition: CameraPosition(target: _pickup, zoom: 12),
            markers: _markers,
            polylines: _routes,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            onMapCreated: (c) async {
              _map = c;
              await _fitBounds();
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF009640), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => openMapplsNavigation(_pickup),
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text('Navigate pickup'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF111827), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => openMapplsNavigation(_drop),
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('Navigate drop'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


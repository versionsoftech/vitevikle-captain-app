import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _map;

  late final LatLng _pickup;
  late final LatLng _drop;

  late final Set<Marker> _markers;

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
        backgroundColor: const Color(0xFF369D01),
        foregroundColor: Colors.white,
        title: Text(name),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: _pickup, zoom: 12),
        markers: _markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onMapCreated: (c) async {
          _map = c;
          await _fitBounds();
        },
      ),
    );
  }
}


import 'dart:async';
import 'package:vite_captain/widgets/vite_loader.dart';

import 'package:flutter/material.dart';
import 'package:vite_captain/maps/mappls_geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vite_captain/maps/mappls_map.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({
    super.key,
    required this.title,
    this.initialLat,
    this.initialLng,
  });

  final String title;
  final double? initialLat;
  final double? initialLng;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final Completer<MapplsViewController> _mapController =
      Completer<MapplsViewController>();

  late LatLng _cameraTarget;
  bool _loadingAddress = false;
  String _addressTitle = 'Locating...';
  String _addressSubtitle = '';

  @override
  void initState() {
    super.initState();
    _cameraTarget = LatLng(
      widget.initialLat ?? 30.3398,
      widget.initialLng ?? 76.3869,
    );
    _reverseGeocode(_cameraTarget);
  }

  Future<void> _reverseGeocode(LatLng latLng) async {
    if (_loadingAddress) return;
    setState(() {
      _loadingAddress = true;
    });

    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      if (!mounted) return;

      final p = placemarks.isNotEmpty ? placemarks.first : null;
      final title = (p?.street?.trim().isNotEmpty == true)
          ? p!.street!.trim()
          : (p?.name?.trim().isNotEmpty == true)
              ? p!.name!.trim()
              : 'Selected location';

      final subtitleParts = <String>[
        if (p?.subLocality?.trim().isNotEmpty == true) p!.subLocality!.trim(),
        if (p?.locality?.trim().isNotEmpty == true) p!.locality!.trim(),
        if (p?.administrativeArea?.trim().isNotEmpty == true)
          p!.administrativeArea!.trim(),
      ];

      setState(() {
        _addressTitle = title;
        _addressSubtitle = subtitleParts.join(', ');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addressTitle = 'Selected location';
        _addressSubtitle =
            'Lat: ${latLng.latitude.toStringAsFixed(5)}, Lng: ${latLng.longitude.toStringAsFixed(5)}';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingAddress = false;
      });
    }
  }

  Future<void> _moveToCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final next = LatLng(pos.latitude, pos.longitude);
      _cameraTarget = next;
      if (_mapController.isCompleted) {
        final c = await _mapController.future;
        await c.animateCamera(CameraUpdate.newLatLngZoom(next, 16));
      }
      await _reverseGeocode(next);
    } catch (_) {}
  }

  String get _fullAddress {
    if (_addressSubtitle.trim().isEmpty) return _addressTitle;
    return '$_addressTitle, $_addressSubtitle';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MapplsView(
              initialCameraPosition: CameraPosition(
                target: _cameraTarget,
                zoom: 16,
              ),
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
              },
              onCameraMove: (position) {
                _cameraTarget = position.target;
              },
              onCameraIdle: () {
                _reverseGeocode(_cameraTarget);
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
            ),
          ),
          const Center(
            child: Icon(Icons.location_pin, size: 42, color: Colors.red),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                  InkWell(
                    onTap: _moveToCurrentLocation,
                    child: Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.my_location, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (_loadingAddress)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: ViteLoader(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, color: Color(0xFFEF4444)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _addressTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _addressSubtitle.trim().isEmpty
                                    ? 'Lat: ${_cameraTarget.latitude.toStringAsFixed(5)}, Lng: ${_cameraTarget.longitude.toStringAsFixed(5)}'
                                    : _addressSubtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(
                          context,
                          <String, dynamic>{
                            'address': _fullAddress,
                            'lat': _cameraTarget.latitude,
                            'lng': _cameraTarget.longitude,
                          },
                        );
                      },
                      child: const Text(
                        'Confirm Location',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

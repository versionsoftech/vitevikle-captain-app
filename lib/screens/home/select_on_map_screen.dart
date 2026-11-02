import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vite_captain/maps/mappls_geocoding.dart';
import 'package:vite_captain/maps/mappls_map.dart';
import 'package:vite_captain/screens/home/drop_location_screen.dart';

class SelectOnMapScreen extends StatefulWidget {
  const SelectOnMapScreen({super.key});

  @override
  State<SelectOnMapScreen> createState() => _SelectOnMapScreenState();
}

class _SelectOnMapScreenState extends State<SelectOnMapScreen> {
  final Completer<MapplsViewController> _controller =
      Completer<MapplsViewController>();

  static const LatLng _defaultTarget = LatLng(30.3398, 76.3869);
  LatLng _cameraTarget = _defaultTarget;

  bool _geocoding = false;
  String _addressTitle = '...';
  String _addressSubtitle = '';

  Future<void> _reverseGeocode(LatLng latLng) async {
    if (_geocoding) return;
    _geocoding = true;

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

      final parts = <String>[
        if (p?.subLocality?.trim().isNotEmpty == true) p!.subLocality!.trim(),
        if (p?.locality?.trim().isNotEmpty == true) p!.locality!.trim(),
        if (p?.administrativeArea?.trim().isNotEmpty == true)
          p!.administrativeArea!.trim(),
        if (p?.postalCode?.trim().isNotEmpty == true) p!.postalCode!.trim(),
      ];

      setState(() {
        _addressTitle = title;
        _addressSubtitle = parts.join(', ');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addressTitle = 'Selected location';
        _addressSubtitle =
            'Lat: ${latLng.latitude.toStringAsFixed(5)}, Lng: ${latLng.longitude.toStringAsFixed(5)}';
      });
    } finally {
      _geocoding = false;
    }
  }

  String get _selectedAddress {
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
              initialCameraPosition: const CameraPosition(
                target: _defaultTarget,
                zoom: 16,
              ),
              onMapCreated: (c) {
                if (!_controller.isCompleted) {
                  _controller.complete(c);
                }
              },
              onCameraMove: (pos) {
                _cameraTarget = pos.target;
              },
              onCameraIdle: () {
                _reverseGeocode(_cameraTarget);
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
          const Center(
            child: Icon(
              Icons.location_pin,
              size: 40,
              color: Colors.red,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topLeft,
                child: InkWell(
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
                          'Select your location',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DropLocationScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Change',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                        const Icon(
                          Icons.location_on,
                          color: Color(0xFFEF4444),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _addressTitle,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _addressSubtitle.trim().isEmpty
                                    ? 'Lat: ${_cameraTarget.latitude.toStringAsFixed(5)}, Lng: ${_cameraTarget.longitude.toStringAsFixed(5)}'
                                    : _addressSubtitle,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
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
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(
                          context,
                          <String, dynamic>{
                            'address': _selectedAddress,
                            'lat': _cameraTarget.latitude,
                            'lng': _cameraTarget.longitude,
                          },
                        );
                      },
                      child: const Text(
                        'Select Drop',
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


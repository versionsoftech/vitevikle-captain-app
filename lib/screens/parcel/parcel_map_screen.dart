import 'dart:async';
import 'package:vite_captain/widgets/vite_loader.dart';

import 'package:flutter/material.dart';
import 'package:vite_captain/maps/mappls_routes.dart';
import 'package:vite_captain/maps/mappls_geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vite_captain/maps/mappls_map.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/vehicle_type_api.dart';
import 'package:vite_captain/widgets/cancellation_reason_sheet.dart';
import 'package:vite_captain/widgets/wallet_insufficient_dialog.dart';

class ParcelMapScreen extends StatefulWidget {
  const ParcelMapScreen({super.key, required this.parcel});

  final Map<String, dynamic> parcel;

  @override
  State<ParcelMapScreen> createState() => _ParcelMapScreenState();
}

class _ParcelMapScreenState extends State<ParcelMapScreen> {

  final SessionService _sessionService = const SessionService();

  MapplsViewController? _map;
  bool _loading = true;

  LatLng? _driverLatLng;
  LatLng? _pickupLatLng;
  LatLng? _dropLatLng;

  double? _driverToPickupKm;

  String? _pickupDisplayAddress;

  Set<Marker> _markers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};

  Timer? _statusTimer;
  String _driverStatus = '';
  String _userStatus = '';
  bool _acceptingParcel = false;
  String _driverVehicleType = '';

  String _asTrimmed(dynamic v) => v == null ? '' : v.toString().trim();

  bool _looksLikeObjectId(String value) {
    return RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(value.trim());
  }

  String _normalizeVehicleForMatch(dynamic value) {
    final s = _asTrimmed(value).toLowerCase();
    if (s.isEmpty) return s;
    // Bike family
    if (s.contains('two wheeler') ||
        (s.contains('two') && s.contains('wheel')) ||
        (s.contains('2') && s.contains('wheel')) ||
        s.contains('bike') ||
        s.contains('bicycle') ||
        s.contains('scooter') ||
        s.contains('motor') ||
        s.contains('moto')) {
      return 'bike';
    }
    // Car family
    if (s.contains('four wheeler') ||
        (s.contains('four') && s.contains('wheel')) ||
        (s.contains('4') && s.contains('wheel')) ||
        s.contains('car') ||
        s.contains('suv') ||
        s.contains('sedan') ||
        s.contains('hatchback')) {
      return 'car';
    }
    return s;
  }

  String _requestVehicleFromParcel() {
    final p = widget.parcel;
    return _asTrimmed(
      p['vehicle_slug'] ??
          p['vehicleSlug'] ??
          p['vehicle_type_name'] ??
          p['vehicleTypeName'] ??
          p['vehicle_name'] ??
          p['vehicleName'] ??
          p['vehicle_type'] ??
          p['vehicleType'],
    );
  }

  bool _isStrictVehicleTypeMatch() {
    final driverType = _normalizeVehicleForMatch(_driverVehicleType);
    final reqType = _normalizeVehicleForMatch(_requestVehicleFromParcel());
    final match = driverType.isEmpty || reqType.isEmpty || driverType == reqType;
    print('PARCEL_MAP_VEHICLE_MATCH driver=$driverType request=$reqType match=$match');
    return match;
  }

  bool _isStaleParcelAcceptMessage(String message) {
    final m = message.toLowerCase();
    return m.contains('already taken') || m.contains('already assigned') || m.contains('not found');
  }

  Future<void> _loadDriverVehicleType() async {
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;
      final resp = await const ApiService().getDriverProfile(token: token);
      final data = resp['success'] == true && resp['data'] is Map ? resp['data'] as Map : null;
      if (data == null) return;
      String vehicleType = _asTrimmed(data['vehicleType'] ?? data['vehicle_type'] ?? data['vehicle_type_name'] ?? data['vehicleTypeName']);
      String vehicleTypeId = '';
      final vehicleInfo = data['vehicleInfo'];
      if (vehicleInfo is Map) {
        vehicleTypeId = _asTrimmed(vehicleInfo['vehicleType'] ?? vehicleInfo['vehicle_type_id']);
        final nestedVehicleName = _asTrimmed(vehicleInfo['vehicleTypeName'] ?? vehicleInfo['vehicle_type_name'] ?? vehicleInfo['name'] ?? vehicleInfo['slug']);
        if (vehicleType.isEmpty && nestedVehicleName.isNotEmpty) {
          vehicleType = nestedVehicleName;
        }
      }
      final driverVehicleInfo = data['driverVehicleInfo'];
      if (driverVehicleInfo is Map) {
        if (vehicleTypeId.isEmpty) {
          vehicleTypeId = _asTrimmed(driverVehicleInfo['vehicle_type_id'] ?? driverVehicleInfo['vehicleTypeId']);
        }
        final driverVehicleInfoName = _asTrimmed(driverVehicleInfo['vehicle_type'] ?? driverVehicleInfo['vehicleType'] ?? driverVehicleInfo['vehicle_type_name'] ?? driverVehicleInfo['vehicleTypeName']);
        if (vehicleType.isEmpty && driverVehicleInfoName.isNotEmpty) {
          vehicleType = driverVehicleInfoName;
        }
      }
      if (_looksLikeObjectId(vehicleType)) {
        vehicleTypeId = vehicleTypeId.isNotEmpty ? vehicleTypeId : vehicleType;
        vehicleType = '';
      }
      if (vehicleType.isEmpty && vehicleTypeId.isNotEmpty) {
        final details = await const VehicleTypeApi().getVehicleTypeById(vehicleTypeId: vehicleTypeId);
        vehicleType = _asTrimmed(details?.slug.trim().isNotEmpty == true ? details?.slug : details?.name);
      }
      if (!mounted) return;
      setState(() {
        _driverVehicleType = vehicleType;
      });
    } catch (_) {}
  }

  Icon _parcelIcon(String desc) {
    final d = desc.toLowerCase();
    if (d.contains('box')) return const Icon(Icons.inventory_2, color: const Color(0xFF009640));
    if (d.contains('wood') || d.contains('timber')) return const Icon(Icons.forest, color: Colors.brown);
    if (d.contains('document')) return const Icon(Icons.description, color: Colors.blue);
    return const Icon(Icons.local_shipping, color: const Color(0xFF009640));
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(v);
      } catch (_) {
        return null;
      }
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
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

  Future<String?> _reverseGeocode(LatLng latLng) async {
    try {
      final places = await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
      if (places.isEmpty) return null;
      final p = places.first;
      final parts = <String>[
        if ((p.name ?? '').trim().isNotEmpty) (p.name ?? '').trim(),
        if ((p.subLocality ?? '').trim().isNotEmpty) (p.subLocality ?? '').trim(),
        if ((p.locality ?? '').trim().isNotEmpty) (p.locality ?? '').trim(),
        if ((p.administrativeArea ?? '').trim().isNotEmpty) (p.administrativeArea ?? '').trim(),
        if ((p.postalCode ?? '').trim().isNotEmpty) (p.postalCode ?? '').trim(),
        if ((p.country ?? '').trim().isNotEmpty) (p.country ?? '').trim(),
      ];
      final joined = parts.join(', ').trim();
      return joined.isEmpty ? null : joined;
    } catch (_) {
      return null;
    }
  }

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

  Future<void> _loadMapData() async {
    final p = widget.parcel;

    LatLng? driverLatLng;
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      driverLatLng = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      driverLatLng = null;
    }

    final pickupNode = p['pickup'];
    final dropNode = p['drop'];

    final pickupLatLng = _parseLatLng(pickupNode) ?? _parseLatLng(p['pickup_location']);
    final dropLatLng = _parseLatLng(dropNode) ?? _parseLatLng(p['drop_location']);

    final pickupAddress = pickupNode is Map ? _asTrimmed(pickupNode['address']) : _asTrimmed(pickupNode);
    final dropAddress = dropNode is Map ? _asTrimmed(dropNode['address']) : _asTrimmed(dropNode);

    LatLng? resolvedPickup = pickupLatLng;
    LatLng? resolvedDrop = dropLatLng;

    if (resolvedPickup == null && pickupAddress.isNotEmpty) {
      resolvedPickup = await _geocodeAddress(pickupAddress);
    }
    if (resolvedDrop == null && dropAddress.isNotEmpty) {
      resolvedDrop = await _geocodeAddress(dropAddress);
    }

    if (!mounted) return;

    _driverLatLng = driverLatLng;
    _pickupLatLng = resolvedPickup;
    _dropLatLng = resolvedDrop;

    _driverStatus = _asTrimmed(p['driver_status'] ?? p['driverStatus']);
    _userStatus = _asTrimmed(p['user_status'] ?? p['userStatus']);

    _refreshStatusPolling();

    final pickupRawAddress = _pickupAddress();
    final hasPlusCode = pickupRawAddress.contains('+');
    if (hasPlusCode && _pickupLatLng != null) {
      _pickupDisplayAddress = _asTrimmed(p['pickup_address'] ?? p['full_address'] ?? p['pickup_full_address']);
      _pickupDisplayAddress = _pickupDisplayAddress!.trim().isEmpty ? null : _pickupDisplayAddress;
      _pickupDisplayAddress ??= await _reverseGeocode(_pickupLatLng!);
      _pickupDisplayAddress ??= pickupRawAddress;
    } else {
      _pickupDisplayAddress = pickupRawAddress;
    }

    if (_driverLatLng != null && _pickupLatLng != null) {
      try {
        final meters = Geolocator.distanceBetween(
          _driverLatLng!.latitude,
          _driverLatLng!.longitude,
          _pickupLatLng!.latitude,
          _pickupLatLng!.longitude,
        );
        _driverToPickupKm = meters / 1000.0;
      } catch (_) {
        _driverToPickupKm = null;
      }
    }

    final markers = <Marker>{
      if (_driverLatLng != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      if (_pickupLatLng != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
    };

    _markers = markers;

    if (_driverLatLng != null && _pickupLatLng != null) {
      await _buildRoutePolyline(_driverLatLng!, _pickupLatLng!);
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
    });

    await _fitBounds();
  }

  void _refreshStatusPolling() {
    final isWaiting = _driverStatus == 'accepted' && _userStatus == 'pending';
    if (!isWaiting) {
      _statusTimer?.cancel();
      _statusTimer = null;
      return;
    }

    if (_statusTimer != null) return;
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollStatus();
    });
    unawaited(_pollStatus());
  }

  Future<void> _pollStatus() async {
    final parcelId = _asTrimmed(widget.parcel['_id'] ?? widget.parcel['id']);
    if (parcelId.isEmpty) return;

    try {
      final resp = await const ApiService().getParcelStatus(parcelId: parcelId);
      if (resp['success'] != true) return;
      final data = resp['data'];
      if (data is! Map) return;

      final nextDriver = _asTrimmed(data['driver_status'] ?? data['driverStatus']);
      final nextUser = _asTrimmed(data['user_status'] ?? data['userStatus']);

      if (!mounted) return;
      final changed = nextDriver != _driverStatus || nextUser != _userStatus;
      if (changed) {
        setState(() {
          _driverStatus = nextDriver;
          _userStatus = nextUser;
        });
      }

      if (nextUser == 'accepted') {
        _statusTimer?.cancel();
        _statusTimer = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer accepted. Ride confirmed.')),
        );
        Navigator.pop(context, true);
        return;
      }

      if (nextUser == 'rejected') {
        _statusTimer?.cancel();
        _statusTimer = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer rejected the request')),
        );
        Navigator.pop(context, false);
        return;
      }
    } catch (_) {}
  }

  Future<void> _fitBounds() async {
    if (_map == null) return;
    final driver = _driverLatLng;
    final pickup = _pickupLatLng;

    final points = <LatLng>[
      if (driver != null) driver,
      if (pickup != null) pickup,
    ];
    if (points.isEmpty) return;

    if (points.length == 1) {
      try {
        await _map!.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      } catch (_) {}
      return;
    }

    final minLat = points.map((e) => e.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = points.map((e) => e.latitude).reduce((a, b) => a > b ? a : b);
    final minLng = points.map((e) => e.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = points.map((e) => e.longitude).reduce((a, b) => a > b ? a : b);

    final sw = LatLng(minLat, minLng);
    final ne = LatLng(maxLat, maxLng);
    try {
      await _map!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: sw, northeast: ne),
          70,
        ),
      );
    } catch (_) {}
  }

  Future<void> _buildRoutePolyline(LatLng origin, LatLng destination) async {
    try {
      final route = await fetchMapplsRoute(origin, destination);
      if (route == null) {
        return;
      }

      final points = route.points;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('driver_to_pickup'),
          points: points,
          color: Theme.of(context).colorScheme.onSurface,
          width: 4,
        ),
      };
    } catch (_) {}
  }

  String _pickupAddress() {
    final pickupNode = widget.parcel['pickup'];
    if (pickupNode is Map) {
      return _asTrimmed(pickupNode['address']);
    }
    return _asTrimmed(pickupNode);
  }

  String _pickupAddressForUi() {
    final v = (_pickupDisplayAddress ?? '').trim();
    if (v.isNotEmpty) return v;
    final raw = _pickupAddress().trim();
    if (raw.isEmpty) return '-';
    final hasPlus = raw.contains('+');
    if (!hasPlus) return raw;
    final fallback = _asTrimmed(
      widget.parcel['pickup_address'] ?? widget.parcel['full_address'] ?? widget.parcel['pickup_full_address'],
    );
    return fallback.trim().isEmpty ? 'Fetching address...' : fallback.trim();
  }

  String _dropAddress() {
    final dropNode = widget.parcel['drop'];
    if (dropNode is Map) {
      return _asTrimmed(dropNode['address']);
    }
    return _asTrimmed(dropNode);
  }

  String _distanceText() {
    final km = _driverToPickupKm;
    if (km == null) return '0.0';
    if (km.isNaN || km.isInfinite) return '0.0';
    return km.toStringAsFixed(1);
  }

  Future<void> _callCustomer() async {
    final p = _asTrimmed(
      widget.parcel['receiver_phone'] ??
          widget.parcel['receiverPhone'] ??
          widget.parcel['sender_phone'] ??
          widget.parcel['senderPhone'] ??
          widget.parcel['phone'] ??
          widget.parcel['mobile'],
    );
    if (p.isEmpty) return;

    final Uri uri = Uri(scheme: 'tel', path: p);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showDetails() async {
    if (!mounted) return;

    final parcel = widget.parcel;
    final pickupDate = _asTrimmed(parcel['pickup_date'] ?? parcel['pickupDate']);
    final pickupTime = _asTrimmed(parcel['pickup_time'] ?? parcel['pickupTime']);
    
    String formattedDate;
    if (pickupDate.isNotEmpty && pickupTime.isNotEmpty) {
      formattedDate = '$pickupDate • $pickupTime';
    } else {
      final created = _parseDate(parcel['pickup_time'] ?? parcel['created_at'] ?? parcel['createdAt']);
      formattedDate = created == null ? '-' : DateFormat('dd MMM yyyy, hh:mm a').format(created);
    }

    final senderName = _asTrimmed(parcel['sender_name'] ?? parcel['senderName'] ?? parcel['sender']);
    final senderPhone = _asTrimmed(parcel['sender_phone'] ?? parcel['senderPhone'] ?? parcel['sender_mobile'] ?? parcel['senderMobile']);
    final receiverName = _asTrimmed(parcel['receiver_name'] ?? parcel['receiverName'] ?? parcel['receiver']);
    final receiverPhone = _asTrimmed(parcel['receiver_phone'] ?? parcel['receiverPhone'] ?? parcel['receiver_mobile'] ?? parcel['receiverMobile']);
    final desc = _asTrimmed(parcel['description']);
    final vehicleName = _asTrimmed(parcel['vehicle_name'] ?? parcel['vehicleName'] ?? parcel['vehicle_title'] ?? parcel['vehicleTitle']);
    final weight = _asTrimmed(parcel['weight'] ?? parcel['parcel_weight'] ?? parcel['parcelWeight']);

    final priceRaw = parcel['price'];
    final price = priceRaw is num ? priceRaw.toDouble() : double.tryParse(_asTrimmed(priceRaw)) ?? 0.0;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Parcel Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on, color: const Color(0xFF009640)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_pickupAddressForUi())),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_dropAddress().isEmpty ? '-' : _dropAddress())),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 10),
              Text('Sender: ${senderName.isEmpty ? '-' : senderName} (${senderPhone.isEmpty ? '-' : senderPhone})'),
              Text('Receiver: ${receiverName.isEmpty ? '-' : receiverName} (${receiverPhone.isEmpty ? '-' : receiverPhone})'),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.inventory_2, color: const Color(0xFF009640)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(desc.isEmpty ? '-' : desc)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Vehicle: ${vehicleName.isEmpty ? '-' : vehicleName}'),
              Text('Weight: ${weight.isEmpty ? '-' : weight} kg'),
              const SizedBox(height: 8),
              Text(
                'Price: ₹${price.toStringAsFixed(2)}',
                style: const TextStyle(color: const Color(0xFF009640), fontWeight: FontWeight.bold),
              ),
              Text('Date: $formattedDate'),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _acceptParcel() async {
    final parcelId = _asTrimmed(widget.parcel['_id'] ?? widget.parcel['id']);
    if (parcelId.isEmpty) return;
    if (_acceptingParcel) return;
    await _loadDriverVehicleType();
    if (!_isStrictVehicleTypeMatch()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This parcel is not for your vehicle type')),
      );
      Navigator.pop(context, false);
      return;
    }
    _acceptingParcel = true;

    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;

      // New confirmation flow (backward compatible)
      final resp = await const ApiService().driverAcceptParcel(token: token, parcelId: parcelId);
      print('PARCEL_ACCEPT_MAP driverAcceptParcel => $resp');
      if (!mounted) return;

      final data = resp['data'];
      final ok = resp['success'] == true ||
          resp['status'] == true ||
          _asTrimmed(resp['success']).toLowerCase() == 'true' ||
          _asTrimmed(resp['status']).toLowerCase() == 'true' ||
          _asTrimmed(resp['driver_status'] ?? resp['driverStatus']).toLowerCase() == 'accepted' ||
          (data is Map && _asTrimmed(data['driver_status'] ?? data['driverStatus']).toLowerCase() == 'accepted');

      if (ok) {
        if (data is Map) {
          setState(() {
            _driverStatus = _asTrimmed(data['driver_status'] ?? data['driverStatus']);
            _userStatus = _asTrimmed(data['user_status'] ?? data['userStatus']);
          });
        } else {
          setState(() {
            _driverStatus = 'accepted';
            _userStatus = 'pending';
          });
        }
        _refreshStatusPolling();
        return;
      }

      // Fallback to legacy accept if confirmation endpoint fails
      final fallback = await const ApiService().acceptParcelRequest(token: token, parcelId: parcelId);
      print('PARCEL_ACCEPT_MAP acceptParcelRequest => $fallback');
      if (!mounted) return;
      final fallbackData = fallback['data'];
      final fallbackOk = fallback['success'] == true ||
          fallback['status'] == true ||
          _asTrimmed(fallback['success']).toLowerCase() == 'true' ||
          _asTrimmed(fallback['status']).toLowerCase() == 'true' ||
          _asTrimmed(fallback['driver_status'] ?? fallback['driverStatus']).toLowerCase() == 'accepted' ||
          (fallbackData is Map && _asTrimmed(fallbackData['driver_status'] ?? fallbackData['driverStatus']).toLowerCase() == 'accepted');
      if (fallbackOk) {
        Navigator.pop(context, true);
        return;
      }

      final msg = (resp['message'] ?? fallback['message'] ?? '').toString();
      if (isWalletInsufficientMessage(msg)) {
        await showWalletInsufficientDialog(context, message: msg);
        return;
      }

      if (_isStaleParcelAcceptMessage(msg)) {
        Navigator.pop(context, true);
        return;
      }

      print('PARCEL_ACCEPT_MAP failure snackbar resp=$resp fallback=$fallback');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to accept parcel')),
      );
    } catch (_) {
    } finally {
      _acceptingParcel = false;
    }
  }

  Future<void> _cancelWaiting() async {
    final parcelId = _asTrimmed(widget.parcel['_id'] ?? widget.parcel['id']);
    if (parcelId.isEmpty) return;
    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;

      final picked = await CancellationReasonSheet.show(
        context: context,
        type: 'driver',
        title: 'Cancel',
        confirmText: 'Cancel',
      );
      if (picked == null) return;

      final resp = await const ApiService().driverCancelParcel(
        token: token,
        parcelId: parcelId,
        cancellationReasonId: picked['cancellation_reason_id'],
        reason: picked['reason'],
        note: picked['note'],
      );
      if (!mounted) return;
      if (resp['success'] == true) {
        _statusTimer?.cancel();
        _statusTimer = null;
        setState(() {
          _driverStatus = 'cancelled';
          _userStatus = 'pending';
        });
        Navigator.pop(context, false);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((resp['message'] ?? 'Unable to cancel').toString())),
      );
    } catch (_) {}
  }

  Future<void> _rejectParcel() async {
    final parcelId = _asTrimmed(widget.parcel['_id'] ?? widget.parcel['id']);
    if (parcelId.isEmpty) return;

    try {
      final token = (await _sessionService.getToken() ?? '').trim();
      if (token.isEmpty) return;

      await const ApiService().rejectParcelRequest(token: token, parcelId: parcelId);
      if (!mounted) return;
      Navigator.pop(context, false);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadDriverVehicleType());
    unawaited(_loadMapData());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _statusTimer = null;
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parcel = widget.parcel;
    final parcelId = _asTrimmed(parcel['_id'] ?? parcel['id']);
    final desc = _asTrimmed(parcel['description']);
    final title = desc.isEmpty ? 'Package' : desc;
    final status = _asTrimmed(parcel['status']).isEmpty ? 'Pending' : _asTrimmed(parcel['status']);

    final pickupDate = _asTrimmed(parcel['pickup_date'] ?? parcel['pickupDate']);
    final pickupTime = _asTrimmed(parcel['pickup_time'] ?? parcel['pickupTime']);
    
    String timeText;
    if (pickupDate.isNotEmpty && pickupTime.isNotEmpty) {
      timeText = '$pickupDate • $pickupTime';
    } else {
      final created = _parseDate(parcel['pickup_time'] ?? parcel['created_at'] ?? parcel['createdAt']);
      timeText = created == null ? '-' : DateFormat('dd MMM yyyy, hh:mm a').format(created);
    }

    final pickupAddr = _pickupAddressForUi();
    final dropAddr = _dropAddress();

    final priceRaw = parcel['price'];
    final price = priceRaw is num ? priceRaw.toDouble() : double.tryParse(_asTrimmed(priceRaw)) ?? 0.0;

    final paymentType = _asTrimmed(parcel['payment_type'] ?? parcel['paymentType'] ?? 'COD');

    final isWaiting = _driverStatus == 'accepted' && _userStatus == 'pending';

    final center = _driverLatLng ?? _pickupLatLng ?? const LatLng(20.5937, 78.9629);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$title${parcelId.isEmpty ? '' : ' • $parcelId'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status,
                          style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _showDetails,
                    child: const Text('Details'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  MapplsView(
                    initialCameraPosition: CameraPosition(target: center, zoom: 13),
                    markers: _markers,
                    polylines: _polylines,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    onMapCreated: (c) {
                      _map = c;
                      unawaited(_fitBounds());
                    },
                  ),
                  if (_loading)
                    const Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        height: 26,
                        width: 26,
                        child: ViteLoader(strokeWidth: 2),
                      ),
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 6)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    _parcelIcon(desc),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '₹${price.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(timeText, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Icon(Icons.location_on, color: const Color(0xFF009640), size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  pickupAddr.isEmpty ? '-' : pickupAddr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Distance ${_distanceText()} km',
                                  style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12.5),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'PaymentType $paymentType',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700, fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _callCustomer,
                                icon: const Icon(Icons.call),
                              ),
                              const SizedBox(width: 6),
                              if (isWaiting)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Waiting for customer response...',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 10),
                                      ElevatedButton(
                                        onPressed: _cancelWaiting,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w900)),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _rejectParcel,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w900)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _acceptParcel,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF009640),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w900)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


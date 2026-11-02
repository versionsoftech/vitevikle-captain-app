import 'dart:async';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vite_captain/maps/mappls_map.dart';
import 'package:vite_captain/maps/mappls_routes.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';
import 'package:vite_captain/screens/chat/ride_chat_screen.dart';
import 'package:provider/provider.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/location_service.dart';
import 'package:vite_captain/screens/home/navigation_map_screen.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/services/chat_notification_provider.dart';
import 'package:vite_captain/widgets/send_ride_notification_sheet.dart';

class PickupMapScreen extends StatefulWidget {
  final Map<String, dynamic> ride;
  final int arrivalMinutes;

  const PickupMapScreen({
    super.key,
    required this.ride,
    required this.arrivalMinutes,
  });

  @override
  State<PickupMapScreen> createState() => _PickupMapScreenState();
}

class _PickupMapScreenState extends State<PickupMapScreen> {
  static const themeGreen = Color(0xFF009640);

  final LocationService _locationService = const LocationService();

  MapplsViewController? _map;
  LatLng? _driverLatLng;
  LatLng? _pickupLatLng;

  Set<Marker> _markers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};

  bool _loading = true;
  String? _distanceText;
  String? _durationText;

  IO.Socket? _cancelSocket;
  Timer? _cancelPollTimer;
  bool _handlingUserCancel = false;

  String get _rideId =>
      (widget.ride['_id'] ?? widget.ride['id'] ?? '').toString().trim();

  Future<void> _sendEta() async {
    final rideId = _rideId;
    if (rideId.isEmpty) return;
    final startedAt = DateTime.now().toUtc().toIso8601String();
    final res = await const ApiService().setRideEta(
      rideId: rideId,
      etaMinutes: widget.arrivalMinutes,
    );

    if (res['success'] != true) return;

    try {
      final socket = _cancelSocket;
      if (socket != null && socket.connected) {
        socket.emit('driver_eta_updated', {
          'ride_id': rideId,
          'rideId': rideId,
          'eta_minutes': widget.arrivalMinutes,
          'etaMinutes': widget.arrivalMinutes,
          'started_at': startedAt,
          'etaStartTime': startedAt,
        });
        socket.emit('etaUpdated', {
          'rideId': rideId,
          'ride_id': rideId,
          'etaMinutes': widget.arrivalMinutes,
          'eta_minutes': widget.arrivalMinutes,
          'started_at': startedAt,
          'etaStartTime': startedAt,
        });
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _connectCancelListener() async {
    final rideId = _rideId;
    if (rideId.isEmpty) return;
    final driverId = (await SessionService().getDriverId() ?? '').toString().trim();

    try {
      final socket = IO.io(
        'https://adm.vitevikle.com',
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': true,
          'reconnection': true,
        },
      );
      _cancelSocket = socket;
      socket.connect();

      void joinRooms() {
        if (driverId.isNotEmpty) {
          socket.emit('join_driver', {'driver_id': driverId, 'driverId': driverId});
          socket.emit('joinPilot', driverId);
        }
        socket.emit('joinRide', {'rideId': rideId});
        socket.emit('join_ride', {'ride_id': rideId, 'rideId': rideId});
      }

      socket.on('connect', (_) => joinRooms());
      joinRooms();

      void onCancelled(dynamic data) {
        if (!mounted || _handlingUserCancel) return;
        if (data is! Map) return;
        final rid = (data['rideId'] ?? data['ride_id'] ?? '').toString().trim();
        if (rid.isNotEmpty && rid != rideId) return;
        final by = (data['cancelled_by'] ?? data['cancelledBy'] ?? '').toString().trim().toLowerCase();
        final message = (data['message'] ?? '').toString().trim();
        _handleRideCancelled(
          message: message.isNotEmpty
              ? message
              : (by == 'user' ? 'Ride cancelled by rider' : 'Ride cancelled'),
        );
      }

      socket.on('ride_cancelled', onCancelled);
      socket.on('rideCancelled', onCancelled);
      socket.on('rideStatusChanged', (data) {
        if (data is! Map) return;
        final status = (data['status'] ?? '').toString().trim().toLowerCase();
        if (status == 'cancelled' || status == 'canceled') {
          onCancelled(data);
        }
      });
    } catch (_) {
      return;
    }
  }

  void _startCancelPolling() {
    _cancelPollTimer?.cancel();
    _cancelPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _pollActiveRideStatus();
    });
    _pollActiveRideStatus();
  }

  Future<void> _pollActiveRideStatus() async {
    if (!mounted || _handlingUserCancel) return;
    final rideId = _rideId;
    if (rideId.isEmpty) return;

    try {
      final driverId = (await SessionService().getDriverId() ?? '').toString().trim();
      if (driverId.isNotEmpty) {
        final resp = await const ApiService().getMyActiveRide(driverId: driverId);
        if (!mounted || _handlingUserCancel) return;
        if (resp['success'] == true) {
          final ride = resp['ride'];
          if (ride == null) {
            _handleRideCancelled(message: 'Ride cancelled by rider');
            return;
          }
          if (ride is Map) {
            final activeId = (ride['_id'] ?? ride['id'] ?? '').toString().trim();
            final status = (ride['status'] ?? '').toString().trim().toLowerCase();
            if ((activeId.isNotEmpty && activeId != rideId) ||
                status == 'cancelled' ||
                status == 'canceled') {
              _handleRideCancelled(message: 'Ride cancelled by rider');
              return;
            }
          }
        }
      }

      final statusRes = await const ApiService().getRideStatus(rideId: rideId);
      if (!mounted || _handlingUserCancel) return;
      final dataNode = statusRes['data'];
      final status = (statusRes['status'] ??
              statusRes['ride_status'] ??
              (dataNode is Map ? dataNode['status'] : null) ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      if (status == 'cancelled' || status == 'canceled') {
        _handleRideCancelled(message: 'Ride cancelled by rider');
      }
    } catch (_) {
      return;
    }
  }

  void _handleRideCancelled({required String message}) {
    if (_handlingUserCancel) return;
    _handlingUserCancel = true;
    _cancelPollTimer?.cancel();
    _cancelPollTimer = null;
    try {
      _cancelSocket?.dispose();
    } catch (_) {}
    _cancelSocket = null;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFFB91C1C),
      ),
    );

    Navigator.of(context).popUntil((route) => route.isFirst);
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

  Future<void> _load() async {
    final pickup = _parseLatLng(widget.ride['pickup']);
    if (pickup == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
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
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: [driver!, pickup],
            color: themeGreen,
            width: 5,
            geodesic: true,
          ),
        };
      });

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

  Future<void> _loadRoute(LatLng origin, LatLng destination) async {
    try {
      final route = await fetchMapplsRoute(origin, destination);
      if (route == null) return;

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
      });
    } catch (_) {
      return;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectCancelListener();
      _startCancelPolling();
      _sendEta();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _cancelPollTimer?.cancel();
    _cancelPollTimer = null;
    try {
      _cancelSocket?.dispose();
    } catch (_) {}
    _cancelSocket = null;
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userNode = widget.ride['user'];
    final userMap = userNode is Map ? userNode : const {};
    final userId = (userMap['_id'] ?? userMap['id'] ?? widget.ride['userId'] ?? widget.ride['user_id'] ?? '')
        .toString()
        .trim();
    final name = (userMap['name'] ?? widget.ride['customerName'] ?? widget.ride['userName'] ?? widget.ride['name'] ?? 'Customer')
        .toString()
        .trim();
    final imageUrl = (userMap['profile_image'] ?? widget.ride['customerImage'] ?? widget.ride['user_image'] ?? widget.ride['image'] ?? '')
        .toString()
        .trim();
    final hasImage = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');

    final phone = (userMap['mobile'] ?? userMap['phone'] ?? widget.ride['userMobile'] ?? widget.ride['mobile'] ?? widget.ride['phone'] ?? '')
        .toString()
        .trim();

    final pickupAddress = (widget.ride['pickup_address'] ?? (widget.ride['pickup'] is Map ? widget.ride['pickup']['address'] : null) ?? '')
        .toString()
        .trim();
    final dropAddress = (widget.ride['drop_address'] ?? (widget.ride['drop'] is Map ? widget.ride['drop']['address'] : null) ?? '')
        .toString()
        .trim();

    final ratingValue = widget.ride['rating'];
    final rating = ratingValue is num
        ? ratingValue.toStringAsFixed(1)
        : (double.tryParse(ratingValue?.toString() ?? '')?.toStringAsFixed(1) ?? '4.5');

    final pickupLatLng = _pickupLatLng;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Go to Pick up'),
        backgroundColor: themeGreen,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Send notification',
            onPressed: () => showSendRideNotificationSheet(context, widget.ride),
            icon: const Icon(Icons.notifications_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            MapplsView(
              initialCameraPosition: CameraPosition(
                target: pickupLatLng ?? const LatLng(20.5937, 78.9629),
                zoom: 13,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (controller) {
                _map = controller;
              },
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _BottomRideCard(
                riderName: name.isEmpty ? 'Customer' : name,
                riderImageUrl: hasImage ? imageUrl : null,
                riderId: userId,
                riderPhone: phone,
                pickupAddress: pickupAddress,
                dropAddress: dropAddress,
                distanceText: _distanceText,
                durationText: _durationText,
                ratingText: rating,
                arrivalMinutes: widget.arrivalMinutes,
                ride: widget.ride,
                onGoToPickup: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NavigationMapScreen(
                        ride: widget.ride,
                      ),
                    ),
                  );
                },
                onCancel: () {
                  Navigator.pop(context);
                },
              ),
            ),
            if (_loading)
              const Positioned(
                top: 16,
                right: 16,
                child: SizedBox(
                  height: 22,
                  width: 22,
                  child: ViteLoader(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomRideCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final String riderName;
  final String? riderImageUrl;
  final String riderId;
  final String riderPhone;
  final String pickupAddress;
  final String dropAddress;
  final String? distanceText;
  final String? durationText;
  final String ratingText;
  final int arrivalMinutes;
  final VoidCallback onGoToPickup;
  final VoidCallback onCancel;

  const _BottomRideCard({
    required this.ride,
    required this.riderName,
    required this.riderImageUrl,
    required this.riderId,
    required this.riderPhone,
    required this.pickupAddress,
    required this.dropAddress,
    required this.distanceText,
    required this.durationText,
    required this.ratingText,
    required this.arrivalMinutes,
    required this.onGoToPickup,
    required this.onCancel,
  });

  Widget _miniAction(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    const themeGreen = Color(0xFF009640);

    Future<void> doCall() async {
      final p = riderPhone.trim();
      if (p.isEmpty) {
        return;
      }

      final Uri uri = Uri(scheme: 'tel', path: p);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    Future<void> openChat() async {
      final receiverId = riderId.trim();
      if (receiverId.isEmpty) return;
      final driverId = (await const SessionService().getDriverId())?.trim() ?? '';
      if (!context.mounted || driverId.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RideChatScreen(
            rideId: (ride['_id'] ?? ride['ride_id'] ?? ride['rideId'] ?? '').toString().trim(),
            senderId: driverId,
            receiverId: receiverId,
            senderRole: 'driver',
            title: riderName.trim().isEmpty ? 'Chat' : riderName.trim(),
          ),
        ),
      );
    }

    return Expanded(
      child: InkWell(
        onTap: () {
          if (label.toLowerCase() == 'call') {
            doCall();
            return;
          }
          if (label.toLowerCase() == 'message') {
            openChat();
            return;
          }
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.hideCurrentSnackBar();
          messenger?.showSnackBar(SnackBar(content: Text(label)));
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: label.toLowerCase() == 'message'
              ? Consumer<ChatNotificationProvider>(
                  builder: (context, n, _) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(child: Icon(icon, color: themeGreen, size: 18)),
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
              : Icon(icon, color: themeGreen, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const themeGreen = Color(0xFF009640);

    final hasImage = riderImageUrl != null && (riderImageUrl!.startsWith('http://') || riderImageUrl!.startsWith('https://'));

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 240),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, t, child) {
        return Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: Opacity(opacity: t, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Color(0x1A000000), blurRadius: 18, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  backgroundImage: hasImage ? NetworkImage(riderImageUrl!) : null,
                  child: hasImage
                      ? null
                      : Text(
                          riderName.isNotEmpty ? riderName[0].toUpperCase() : 'C',
                          style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              color: Theme.of(context).colorScheme.surface,
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
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Arriving in $arrivalMinutes min',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
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
                _miniAction(context, icon: Icons.share_outlined, label: 'Share ETA'),
                const SizedBox(width: 10),
                _miniAction(context, icon: Icons.message_outlined, label: 'Message'),
                const SizedBox(width: 10),
                _miniAction(context, icon: Icons.call_outlined, label: 'Call'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AddressRow(
                        dotColor: themeGreen,
                        text: pickupAddress.trim().isEmpty ? 'Pickup location' : pickupAddress.trim(),
                      ),
                      const SizedBox(height: 6),
                      _AddressRow(
                        dotColor: const Color(0xFFFF6B6B),
                        text: dropAddress.trim().isEmpty ? 'Drop location' : dropAddress.trim(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if ((distanceText != null && distanceText!.isNotEmpty) ||
                    (durationText != null && durationText!.isNotEmpty))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (distanceText != null && distanceText!.isNotEmpty)
                          Text(distanceText!, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                        if (durationText != null && durationText!.isNotEmpty)
                          Text(durationText!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: onGoToPickup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Go to Pickup', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE53935),
                        side: const BorderSide(color: Color(0xFFE53935)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final Color dotColor;
  final String text;

  const _AddressRow({required this.dotColor, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          height: 8,
          width: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}


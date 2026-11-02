import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vite_captain/maps/mappls_geocoding.dart';
import 'package:vite_captain/maps/mappls_map.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/widgets/curved_green_app_bar.dart';

const Color _green = Color(0xFF009640);

class TripDetailScreen extends StatelessWidget {
  const TripDetailScreen({
    super.key,
    required this.trip,
    required this.kind,
  });

  final Map<String, dynamic> trip;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final info = TripFacts.from(trip, kind);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _TopBar(number: info.number, status: info.statusLabel, canceled: info.canceled),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                SizedBox(height: 220, child: _RouteMap(pickup: info.pickupPoint, drop: info.dropPoint, pickupAddress: info.pickup, dropAddress: info.drop)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    children: [
                      _StopRow(color: _green, label: 'Pickup', value: info.pickup),
                      const SizedBox(height: 10),
                      _StopRow(color: const Color(0xFFEF4444), label: 'Destination', value: info.drop),
                    ],
                  ),
                ),
                const Divider(height: 24),
                _Section(
                  title: info.kind == 'parcel' ? 'PARCEL DETAIL' : 'RIDE DETAIL',
                  rows: info.detailRows,
                ),
                const Divider(height: 24),
                _Section(title: 'PAYMENT', rows: info.paymentRows),
                if (info.cancelReason.isNotEmpty) ...[
                  const Divider(height: 24),
                  _Section(title: 'CANCELLATION', rows: [TripRow('Reason', info.cancelReason)]),
                ],
                const SizedBox(height: 18),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => TripInvoiceScreen(info: info)),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Invoice', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                  ),
                  if (!info.canceled) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => TripReviewScreen(info: info, trip: trip)),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _green,
                          side: const BorderSide(color: _green, width: 1.4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          info.kind == 'parcel' ? 'Rate delivery' : 'Rate your ride',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TripInvoiceScreen extends StatelessWidget {
  const TripInvoiceScreen({super.key, required this.info});

  final TripFacts info;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: curvedGreenAppBar(title: 'Invoice'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('ViteCaptain', style: TextStyle(color: _green, fontWeight: FontWeight.w900, fontSize: 22)),
                    ),
                    _StatusPill(label: info.statusLabel, canceled: info.canceled),
                  ],
                ),
                const SizedBox(height: 4),
                Text(info.number, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                Text(info.pickup, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Icon(Icons.south, size: 16, color: Color(0xFF9CA3AF)),
                ),
                Text(info.drop, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Divider(height: 28),
                for (final row in info.detailRows) _InvoiceLine(row: row),
                const Divider(height: 28),
                for (final row in info.paymentRows) _InvoiceLine(row: row, emphasize: row.label == 'Total'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final lines = <String>[
                  'ViteCaptain invoice ${info.number}',
                  info.statusLabel,
                  'Pickup: ${info.pickup}',
                  'Destination: ${info.drop}',
                  ...info.detailRows.map((row) => '${row.label}: ${row.value}'),
                  ...info.paymentRows.map((row) => '${row.label}: ${row.value}'),
                ];
                Share.share(lines.join('\n'));
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share invoice', style: TextStyle(fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TripReviewScreen extends StatefulWidget {
  const TripReviewScreen({super.key, required this.info, required this.trip});

  final TripFacts info;
  final Map<String, dynamic> trip;

  @override
  State<TripReviewScreen> createState() => _TripReviewScreenState();
}

class _TripReviewScreenState extends State<TripReviewScreen> {
  int _rating = 0;
  final TextEditingController _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a rating')));
      return;
    }
    setState(() => _busy = true);
    try {
      final reviewerId = (await const SessionService().getDriverId())?.trim() ?? '';
      final user = widget.trip['user'];
      final reviewFor = _text(
        widget.trip['user_id'] ??
            widget.trip['userId'] ??
            widget.trip['rider_id'] ??
            widget.trip['customer_id'] ??
            (user is Map ? user['_id'] ?? user['id'] : null),
      );
      final resp = await const ApiService().submitReview(
        rideId: widget.info.id,
        reviewerId: reviewerId,
        reviewFor: reviewFor,
        rating: _rating,
        tags: const [],
        comment: _comment.text.trim(),
        type: widget.info.kind == 'parcel' ? 'parcel' : 'driver_to_user',
      );
      final ok = resp['status'] == true || resp['success'] == true;
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to submit review. Try again')));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Review submitted')));
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to submit review. Try again')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.info.kind == 'parcel' ? 'Rate delivery' : 'Rate your ride';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: curvedGreenAppBar(title: title),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        children: [
          Text(widget.info.number, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            widget.info.customerName.isEmpty ? 'Customer' : widget.info.customerName,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final selected = index < _rating;
              return IconButton(
                onPressed: () => setState(() => _rating = index + 1),
                icon: Icon(selected ? Icons.star_rounded : Icons.star_outline_rounded, size: 40, color: selected ? _green : const Color(0xFFD1D5DB)),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            minLines: 4,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'Write a review',
              filled: true,
              fillColor: const Color(0xFFF5F7F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: ViteLoader(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit review', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}

class TripRow {
  const TripRow(this.label, this.value);
  final String label;
  final String value;
}

class TripFacts {
  TripFacts({
    required this.id,
    required this.number,
    required this.kind,
    required this.statusLabel,
    required this.canceled,
    required this.pickup,
    required this.drop,
    required this.pickupPoint,
    required this.dropPoint,
    required this.customerName,
    required this.cancelReason,
    required this.detailRows,
    required this.paymentRows,
  });

  final String id;
  final String number;
  final String kind;
  final String statusLabel;
  final bool canceled;
  final String pickup;
  final String drop;
  final LatLng? pickupPoint;
  final LatLng? dropPoint;
  final String customerName;
  final String cancelReason;
  final List<TripRow> detailRows;
  final List<TripRow> paymentRows;

  factory TripFacts.from(Map<String, dynamic> trip, String kind) {
    final rawKind = _text(trip['ride_type'] ?? trip['rideType']).toLowerCase();
    final resolvedKind = rawKind == 'parcel' || rawKind == 'intercity' ? rawKind : (kind == 'parcel' || kind == 'intercity' ? kind : 'ride');
    final status = _text(trip['status']).toLowerCase();
    final canceled = status.contains('cancel') || status == 'rejected' || status == 'expired';
    final delivered = status == 'delivered' || (resolvedKind == 'parcel' && status == 'completed');
    final statusLabel = canceled ? (status == 'expired' ? 'Expired' : 'Canceled') : (delivered ? 'Delivered' : 'Completed');
    final id = _text(trip['_id'] ?? trip['id'] ?? trip['ride_id'] ?? trip['rideId']);
    final booking = _text(trip['booking_id'] ?? trip['bookingId'] ?? trip['order_id'] ?? trip['orderId'] ?? trip['ride_number'] ?? trip['rideNumber']);
    final number = booking.isNotEmpty ? '#$booking' : (id.isEmpty ? '#Trip' : '#${id.length > 6 ? id.substring(id.length - 6) : id}');
    final pickupNode = trip['pickup'] ?? trip['pickup_location'] ?? trip['pickupLocation'] ?? trip['pickup_address'];
    final dropNode = trip['drop'] ?? trip['drop_location'] ?? trip['destination'] ?? trip['drop_address'];
    final when = trip['completed_at'] ?? trip['completedAt'] ?? trip['cancelled_at'] ?? trip['created_at'] ?? trip['createdAt'] ?? trip['date'];
    final vehicle = _text(trip['vehicle_type'] ?? trip['vehicleType'] ?? trip['car_type'] ?? trip['carType']);
    final user = trip['user'];
    final customer = _text(
      trip['user_name'] ??
          trip['userName'] ??
          trip['customer_name'] ??
          trip['sender_name'] ??
          trip['rider_name'] ??
          (user is Map ? user['name'] : null),
    );
    final minutes = _asDouble(trip['duration'] ?? trip['durationMins'] ?? trip['time'] ?? trip['minutes']);
    final hours = minutes <= 0 ? 0 : minutes ~/ 60;
    final mins = minutes <= 0 ? 0 : (minutes % 60).round();
    final durationText = minutes <= 0 ? '-' : '$hours hours $mins Minutes';
    final paymentMethod = _text(trip['payment_method'] ?? trip['paymentMethod'] ?? trip['payment_type'] ?? trip['paymentType']);
    final reason = _text(trip['cancellation_reason'] ?? trip['cancel_reason'] ?? trip['reason'] ?? trip['cancelled_reason']);

    final total = _firstAmount(trip, const ['fare', 'final_fare', 'finalFare', 'final_price', 'total_price', 'price', 'amount', 'accepted_fare']);
    final rows = <TripRow>[
      TripRow(resolvedKind == 'parcel' ? 'Parcel type' : 'Ride type', _titleKind(resolvedKind)),
      TripRow(resolvedKind == 'parcel' ? 'Vehicle' : 'Vehicle', vehicle.isEmpty ? 'Vehicle' : _title(vehicle)),
      if (customer.isNotEmpty) TripRow('Customer', customer),
      TripRow('Hours / Minutes', durationText),
      TripRow('Date & Time', _formatWhen(when)),
      if (paymentMethod.isNotEmpty) TripRow('Payment method', _title(paymentMethod)),
    ];

    final charges = <TripRow?>[
      _moneyRow('Base fare', trip, const ['base_fare', 'baseFare', 'base_price']),
      _moneyRow('Distance charge', trip, const ['distance_charge', 'distanceCharge', 'distance_fare']),
      _moneyRow('Platform fee', trip, const ['platform_fee', 'platformFee', 'platform_charge']),
      _moneyRow('Weather price', trip, const ['weather_price', 'weatherPrice', 'weather_charge']),
      _moneyRow('Waiting charge', trip, const ['waiting_charge', 'waitingCharge']),
      _moneyRow('Toll', trip, const ['toll', 'toll_charge', 'tollCharge']),
      _moneyRow('Tax', trip, const ['tax', 'gst', 'tax_amount']),
      _moneyRow('Discount', trip, const ['discount', 'coupon_discount', 'couponDiscount']),
      _moneyRow('Commission', trip, const ['commission', 'commission_amount', 'commissionAmount']),
    ].whereType<TripRow>().toList();
    charges.add(TripRow('Total', total <= 0 ? '₹0' : '₹${total.toStringAsFixed(total % 1 == 0 ? 0 : 2)}'));

    return TripFacts(
      id: id,
      number: number,
      kind: resolvedKind,
      statusLabel: statusLabel,
      canceled: canceled,
      pickup: _address(pickupNode).isEmpty ? 'Pickup location' : _address(pickupNode),
      drop: _address(dropNode).isEmpty ? 'Destination' : _address(dropNode),
      pickupPoint: _point(
        pickupNode,
        trip['pickup_lat'] ?? trip['pickupLat'] ?? trip['pickup_latitude'] ?? trip['from_lat'] ?? trip['start_lat'],
        trip['pickup_lng'] ?? trip['pickupLng'] ?? trip['pickup_longitude'] ?? trip['from_lng'] ?? trip['start_lng'],
      ),
      dropPoint: _point(
        dropNode,
        trip['drop_lat'] ?? trip['dropLat'] ?? trip['drop_latitude'] ?? trip['to_lat'] ?? trip['end_lat'],
        trip['drop_lng'] ?? trip['dropLng'] ?? trip['drop_longitude'] ?? trip['to_lng'] ?? trip['end_lng'],
      ),
      customerName: customer,
      cancelReason: reason,
      detailRows: rows,
      paymentRows: charges,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.number, required this.status, required this.canceled});

  final String number;
  final String status;
  final bool canceled;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, top + 6, 12, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
            ),
            Expanded(
              child: Text(number, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            ),
            _StatusPill(label: status, canceled: canceled),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.canceled});

  final String label;
  final bool canceled;

  @override
  Widget build(BuildContext context) {
    final color = canceled ? const Color(0xFFB91C1C) : _green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
    );
  }
}

class _RouteMap extends StatefulWidget {
  const _RouteMap({required this.pickup, required this.drop, required this.pickupAddress, required this.dropAddress});

  final LatLng? pickup;
  final LatLng? drop;
  final String pickupAddress;
  final String dropAddress;

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  LatLng? _pickup;
  LatLng? _drop;

  @override
  void initState() {
    super.initState();
    _pickup = widget.pickup;
    _drop = widget.drop;
    _fillMissing();
  }

  Future<void> _fillMissing() async {
    final pickup = _pickup ?? await _geocode(widget.pickupAddress);
    final drop = _drop ?? await _geocode(widget.dropAddress);
    if (!mounted) return;
    if (pickup == _pickup && drop == _drop) return;
    setState(() {
      _pickup = pickup;
      _drop = drop;
    });
  }

  Future<LatLng?> _geocode(String address) async {
    final query = address.trim();
    if (query.isEmpty || query == 'Pickup location' || query == 'Destination') return null;
    try {
      final places = await locationFromAddress(query);
      if (places.isEmpty) return null;
      return LatLng(places.first.latitude, places.first.longitude);
    } catch (_) {
      return null;
    }
  }

  void _frame(MapplsViewController controller) {
    final pickup = _pickup;
    final drop = _drop;
    if (pickup != null && drop != null) {
      final south = pickup.latitude < drop.latitude ? pickup.latitude : drop.latitude;
      final north = pickup.latitude > drop.latitude ? pickup.latitude : drop.latitude;
      final west = pickup.longitude < drop.longitude ? pickup.longitude : drop.longitude;
      final east = pickup.longitude > drop.longitude ? pickup.longitude : drop.longitude;
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)),
          56,
        ),
      );
      return;
    }
    final only = pickup ?? drop;
    if (only != null) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(only, 15));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickup = _pickup;
    final drop = _drop;
    if (pickup == null && drop == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(child: Icon(Icons.map_outlined, color: _green, size: 42)),
      );
    }
    final target = pickup ?? drop!;
    return MapplsView(
      initialCameraPosition: CameraPosition(target: target, zoom: 14),
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      compassEnabled: false,
      onMapCreated: _frame,
      markers: {
        if (pickup != null) Marker(markerId: const MarkerId('pickup'), position: pickup, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
        if (drop != null) Marker(markerId: const MarkerId('drop'), position: drop, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
      },
      polylines: {
        if (pickup != null && drop != null)
          Polyline(polylineId: const PolylineId('route'), points: [pickup, drop], color: _green, width: 5),
      },
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<TripRow> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w800, letterSpacing: 0.6, fontSize: 12)),
          const SizedBox(height: 10),
          for (final row in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(row.label, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface))),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(row.value, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InvoiceLine extends StatelessWidget {
  const _InvoiceLine({required this.row, this.emphasize = false});

  final TripRow row;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700, fontSize: emphasize ? 16 : 14, color: emphasize ? _green : const Color(0xFF111827));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(row.label, style: style)),
          Text(row.value, style: style),
        ],
      ),
    );
  }
}

String _text(dynamic value) => (value ?? '').toString().trim();

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value)) ?? 0;
}

String _address(dynamic node) {
  if (node is Map) {
    return _text(node['address'] ?? node['name'] ?? node['formatted_address'] ?? node['location']);
  }
  final text = _text(node);
  if (text.startsWith('{') || text.startsWith('[')) return '';
  return text;
}

LatLng? _coord(dynamic latRaw, dynamic lngRaw) {
  var lat = _asDouble(latRaw);
  var lng = _asDouble(lngRaw);
  if (lat == 0 && lng == 0) return null;
  if (lat.abs() > 90 || (lat.abs() > 45 && lng.abs() <= 45)) {
    final swap = lat;
    lat = lng;
    lng = swap;
  }
  if (lat.abs() > 90 || lng.abs() > 180 || lat == 0 || lng == 0) return null;
  return LatLng(lat, lng);
}

LatLng? _point(dynamic node, dynamic latFallback, dynamic lngFallback) {
  if (node is Map) {
    final coords = node['coordinates'];
    if (coords is List && coords.length >= 2) {
      final geo = _coord(coords[1], coords[0]);
      if (geo != null) return geo;
    }
    final location = node['location'];
    if (location is Map) {
      final nested = _point(location, null, null);
      if (nested != null) return nested;
    }
    final direct = _coord(node['lat'] ?? node['latitude'], node['lng'] ?? node['lon'] ?? node['longitude']);
    if (direct != null) return direct;
  }
  return _coord(latFallback, lngFallback);
}

double _firstAmount(Map<String, dynamic> trip, List<String> keys) {
  for (final key in keys) {
    final amount = _asDouble(trip[key]);
    if (amount > 0) return amount;
  }
  final payment = trip['payment'] ?? trip['fare_breakup'] ?? trip['fareBreakup'];
  if (payment is Map) {
    for (final key in keys) {
      final amount = _asDouble(payment[key]);
      if (amount > 0) return amount;
    }
  }
  return 0;
}

TripRow? _moneyRow(String label, Map<String, dynamic> trip, List<String> keys) {
  final amount = _firstAmount(trip, keys);
  if (amount <= 0) return null;
  return TripRow(label, '₹${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)}');
}

String _formatWhen(dynamic value) {
  final raw = _text(value);
  if (raw.isEmpty) return '-';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return DateFormat('dd/MM/yyyy, hh:mm a').format(parsed.toLocal());
}

String _title(String value) {
  final cleaned = value.replaceAll('_', ' ').trim();
  if (cleaned.isEmpty) return value;
  return cleaned.split(' ').map((part) {
    if (part.isEmpty) return part;
    return part[0].toUpperCase() + part.substring(1).toLowerCase();
  }).join(' ');
}

String _titleKind(String kind) {
  if (kind == 'intercity') return 'Intercity';
  if (kind == 'parcel') return 'Parcel';
  return 'Ride';
}

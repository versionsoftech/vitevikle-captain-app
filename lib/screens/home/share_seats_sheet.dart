import 'package:flutter/material.dart';
import 'package:vite_captain/models/intercity_request.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/session_service.dart';

class ShareSeatsSheet extends StatefulWidget {
  const ShareSeatsSheet({super.key, required this.ride});

  final IntercityRequestModel ride;

  @override
  State<ShareSeatsSheet> createState() => _ShareSeatsSheetState();
}

class _ShareSeatsSheetState extends State<ShareSeatsSheet> {
  static const _green = Color(0xFF009640);

  final SessionService _session = SessionService();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String _busyId = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = (await _session.getToken() ?? '').trim();
    final res = await const ApiService().getIntercitySeatMatches(token: token, requestId: widget.ride.id);
    if (!mounted) return;
    final data = res['data'];
    setState(() {
      _loading = false;
      _rows = data is List ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
      _error = res['success'] == true ? '' : (res['message'] ?? 'Could not find captains').toString();
    });
  }

  Future<void> _give(Map<String, dynamic> row) async {
    final hostId = (row['host_ride_id'] ?? '').toString();
    if (hostId.isEmpty || _busyId.isNotEmpty) return;
    setState(() => _busyId = hostId);
    final token = (await _session.getToken() ?? '').trim();
    final res = await const ApiService().offerIntercitySeats(
      token: token,
      requestId: widget.ride.id,
      hostRideId: hostId,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busyId = '';
      _error = (res['message'] ?? 'Could not give this ride').toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final persons = widget.ride.persons;
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Give this ride', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '$persons passenger${persons == 1 ? '' : 's'} · captains already going this way with empty seats',
                style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(_error, style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w700)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _green))
                  : _error.isNotEmpty
                      ? const SizedBox.shrink()
                      : _rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No captain on this route has empty seats right now. You can still keep this ride, or pass it after another captain is going the same way.',
                            style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            final name = (row['driver_name'] ?? 'Captain').toString();
                            final empty = row['empty_seats'] ?? 0;
                            final filled = row['seats_filled'] ?? 0;
                            final capacity = row['seat_capacity'] ?? 0;
                            final vehicle = (row['vehicle_type'] ?? '').toString();
                            final number = (row['vehicle_number'] ?? '').toString();
                            final hostId = (row['host_ride_id'] ?? '').toString();
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${vehicle.isEmpty ? 'Car' : vehicle}${number.isEmpty ? '' : ' · $number'}',
                                    style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text((row['pickup'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text((row['drop'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$filled seated · $empty empty · $capacity seats',
                                    style: const TextStyle(color: _green, fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 42,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _green,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: _busyId.isEmpty ? () => _give(row) : null,
                                      child: _busyId == hostId
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Text('Give them this ride', style: TextStyle(fontWeight: FontWeight.w800)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

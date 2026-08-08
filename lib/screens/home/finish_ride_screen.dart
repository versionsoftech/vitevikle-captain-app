import 'package:flutter/material.dart';

class FinishRideScreen extends StatelessWidget {
  final String rideId;
  final Map<String, dynamic>? ride;

  const FinishRideScreen({
    super.key,
    required this.rideId,
    this.ride,
  });

  @override
  Widget build(BuildContext context) {
    final r = ride ?? const <String, dynamic>{};
    final pickupNode = r['pickup'];
    final dropNode = r['drop'];

    final pickupAddress = (r['pickup_address'] ?? (pickupNode is Map ? pickupNode['address'] : null) ?? '').toString().trim();
    final dropAddress = (r['drop_address'] ?? (dropNode is Map ? dropNode['address'] : null) ?? '').toString().trim();

    final userNode = r['user'];
    final userMap = userNode is Map ? userNode : const {};
    final customerName = (userMap['name'] ?? r['customerName'] ?? r['userName'] ?? r['name'] ?? 'Customer').toString().trim();

    final fareValue = r['fare'] ?? r['finalFare'];
    final fare = fareValue is num ? fareValue.toString() : (fareValue?.toString() ?? '');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Finish Ride'),
        backgroundColor: const Color(0xFFFF3B30),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customerName.isEmpty ? 'Customer' : customerName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                rideId.isEmpty ? '' : 'Ride ID: $rideId',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 18),
              if (pickupAddress.isNotEmpty) ...[
                const Text('Pickup', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(pickupAddress),
                const SizedBox(height: 14),
              ],
              if (dropAddress.isNotEmpty) ...[
                const Text('Drop', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(dropAddress),
                const SizedBox(height: 14),
              ],
              if (fare.trim().isNotEmpty) ...[
                const Text('Fare', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(fare),
                const SizedBox(height: 18),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

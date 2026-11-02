import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vite_captain/widgets/vite_loader.dart';

/// Compact upcoming request card: vehicle, fare, pickup, drop, and distances.
class UpcomingOfferCard extends StatefulWidget {
  const UpcomingOfferCard({
    super.key,
    required this.vehicleLabel,
    required this.vehicleIcon,
    required this.fare,
    required this.pickup,
    required this.drop,
    required this.pickupKm,
    required this.dropKm,
    required this.onAccept,
    required this.onIgnore,
  });

  final String vehicleLabel;
  final IconData vehicleIcon;
  final double fare;
  final String pickup;
  final String drop;
  final String pickupKm;
  final String dropKm;
  final Future<void> Function() onAccept;
  final Future<void> Function() onIgnore;

  @override
  State<UpcomingOfferCard> createState() => _UpcomingOfferCardState();
}

class _UpcomingOfferCardState extends State<UpcomingOfferCard> {
  static const Color _green = Color(0xFF009640);
  Timer? _timer;
  int _left = 15;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _left <= 0) {
        _timer?.cancel();
        return;
      }
      setState(() => _left -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _place(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 'Location';
    final first = text.split(',').first.trim();
    return first.isEmpty ? text : first;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fare = widget.fare <= 0 ? '₹0' : '₹${widget.fare.toStringAsFixed(0)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EDF2)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F7EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.vehicleIcon, color: _green, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.vehicleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Extra $fare', style: const TextStyle(color: _green, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 12),
            _stop(
              color: _green,
              icon: Icons.circle,
              title: _place(widget.pickup),
              subtitle: widget.pickup.trim().isEmpty ? 'Pickup location' : widget.pickup.trim(),
            ),
            const SizedBox(height: 10),
            _stop(
              color: const Color(0xFFF97316),
              icon: Icons.location_on_rounded,
              title: _place(widget.drop),
              subtitle: widget.drop.trim().isEmpty ? 'Drop location' : widget.drop.trim(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _kmBox('Pickup', widget.pickupKm)),
                const SizedBox(width: 10),
                Expanded(child: _kmBox('Drop', widget.dropKm)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  child: InkWell(
                    onTap: _busy ? null : () => _run(widget.onIgnore),
                    borderRadius: BorderRadius.circular(14),
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: _green,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: _busy ? null : () => _run(widget.onAccept),
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: _busy
                              ? const SizedBox(width: 18, height: 18, child: ViteLoader(strokeWidth: 2, color: Colors.white))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Accept', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                                    if (_left > 0) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 24,
                                        height: 24,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.22),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text('$_left', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                                      ),
                                    ],
                                  ],
                                ),
                        ),
                      ),
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

  Widget _kmBox(String label, String value) {
    final text = value.trim().isEmpty ? '--' : value.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 2),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      ],
    );
  }

  Widget _stop({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 12, height: 1.25),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

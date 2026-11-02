import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pickup-to-drop rail used on incoming ride cards.
/// The line is painted inside the address block, so it cannot overflow.
class RideRouteRail extends StatefulWidget {
  const RideRouteRail({
    super.key,
    required this.pickup,
    required this.drop,
    this.distanceLabel,
  });

  final String pickup;
  final String drop;
  final String? distanceLabel;

  @override
  State<RideRouteRail> createState() => _RideRouteRailState();
}

class _RideRouteRailState extends State<RideRouteRail> with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final km = (widget.distanceLabel ?? '').trim();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (context, _) => CustomPaint(
                painter: _RailPainter(t: _motion.value),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.pickup,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, color: Color(0xFF111827)),
                ),
                const SizedBox(height: 8),
                if (km.isNotEmpty)
                  Text(
                    km,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6B7280), height: 1.1),
                  ),
                Text(
                  widget.drop,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, color: Color(0xFF111827)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height < 8 || size.width <= 0) return;
    final x = size.width / 2;
    const radius = 4.5;
    final top = radius + 1;
    final bottom = math.max(top + 8, size.height - radius - 1);

    final track = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, top), Offset(x, bottom), track);

    final head = top + ((bottom - top) * t);
    final tail = math.max(top, head - 14);
    final glow = Paint()
      ..color = const Color(0xFF009640)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, tail), Offset(x, head), glow);
    canvas.drawCircle(Offset(x, head), 2.6, Paint()..color = const Color(0xFF009640));

    final dot = Paint()..color = const Color(0xFF009640);
    canvas.drawCircle(Offset(x, top), radius, Paint()..color = const Color(0xFFE7F8EE));
    canvas.drawCircle(Offset(x, top), radius, Paint()
      ..color = const Color(0xFF009640)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    canvas.drawCircle(Offset(x, bottom), radius, dot);
  }

  @override
  bool shouldRepaint(covariant _RailPainter oldDelegate) => oldDelegate.t != t;
}

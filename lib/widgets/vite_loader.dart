import 'package:flutter/material.dart';

/// Three dots that dip one after another, matching the bobbing-dots loader:
/// each dot travels down by 0.625 of its size and back, 1 second, ease-in-out,
/// starting 0.2 seconds after the dot before it.
class ViteLoader extends StatefulWidget {
  final double? size;
  final Color? color;
  final double strokeWidth;
  final Animation<Color?>? valueColor;
  final Color? backgroundColor;
  final double? value;

  const ViteLoader({
    super.key,
    this.size,
    this.color,
    this.strokeWidth = 4,
    this.valueColor,
    this.backgroundColor,
    this.value,
  });

  @override
  State<ViteLoader> createState() => _ViteLoaderState();
}

class _ViteLoaderState extends State<ViteLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  double _dip(int index) {
    final shifted = _bounce.value - (index * 0.2);
    final t = shifted - shifted.floorToDouble();
    if (t <= 0.5) {
      return Curves.easeInOut.transform(t / 0.5);
    }
    return 1 - Curves.easeInOut.transform((t - 0.5) / 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.strokeWidth <= 3 && widget.size == null;
    final scale = widget.size == null ? 1.0 : (widget.size! / 48).clamp(0.75, 1.7);
    final dot = compact ? 5.0 : 12.0 * scale;
    final travel = dot * 0.625;
    final color = widget.color ?? widget.valueColor?.value ?? const Color(0xFF009640);
    final width = compact ? 32.0 : 18.0 + (dot * 3) + (dot * 0.55 * 2);
    final height = dot + travel + 4;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedBuilder(
          animation: _bounce,
          builder: (context, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(3, (index) {
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: dot * 0.22),
                  child: Transform.translate(
                    offset: Offset(0, _dip(index) * travel),
                    child: Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.28),
                            blurRadius: dot * 0.35,
                            offset: Offset(0, dot * 0.12),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class AddStopsScreen extends StatefulWidget {
  const AddStopsScreen({super.key});

  @override
  State<AddStopsScreen> createState() => _AddStopsScreenState();
}

class _AddStopsScreenState extends State<AddStopsScreen> {
  final List<TextEditingController> _stopControllers = <TextEditingController>[];
  final TextEditingController _dropController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _addStop();
  }

  @override
  void dispose() {
    for (final c in _stopControllers) {
      c.dispose();
    }
    _dropController.dispose();
    super.dispose();
  }

  void _addStop() {
    setState(() {
      _stopControllers.add(TextEditingController());
    });
  }

  void _removeStop(int index) {
    setState(() {
      final c = _stopControllers.removeAt(index);
      c.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Drop'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Text('For me'),
                SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down),
              ],
            ),
          ),
        ],
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StopsIndicator(stopsCount: _stopControllers.length),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          children: [
                            _StaticRow(
                              text: 'Your Current Location',
                              textStyle: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFFE5E7EB),
                            ),
                            ListView.builder(
                              itemCount: _stopControllers.length,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemBuilder: (context, index) {
                                return Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _stopControllers[index],
                                            decoration: const InputDecoration(
                                              hintText: 'Add Stop',
                                              border: InputBorder.none,
                                            ),
                                          ),
                                        ),
                                        Icon(Icons.drag_handle, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () => _removeStop(index),
                                          child: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                    if (index != _stopControllers.length - 1)
                                      const Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Color(0xFFE5E7EB),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFFE5E7EB),
                            ),
                            TextField(
                              controller: _dropController,
                              decoration: const InputDecoration(
                                hintText: 'Drop location',
                                border: InputBorder.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () {},
                        icon: Icon(Icons.location_on_outlined, color: Theme.of(context).colorScheme.onSurface),
                        label: Text(
                          'Select on map',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: _addStop,
                        icon: Icon(Icons.add, color: Theme.of(context).colorScheme.onSurface),
                        label: Text(
                          'Add stops',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Center(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 140,
                        width: 190,
                        child: Image.asset(
                          'assets/images/stops_illustration.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.timer_outlined,
                                size: 86,
                                color: Color(0xFFCBD5E1),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'You can take 5 min halts/ stop',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please ensure small stops to avoid wait time fee',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: SizedBox(
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Confirm',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopsIndicator extends StatelessWidget {
  const _StopsIndicator({required this.stopsCount});

  final int stopsCount;

  @override
  Widget build(BuildContext context) {
    final int clampedStops = stopsCount < 0 ? 0 : stopsCount;

    return SizedBox(
      width: 28,
      child: Column(
        children: [
          _dot(context, color: const Color(0xFF009640), filled: false),
          const SizedBox(height: 8),
          const _DottedLine(height: 16),
          const SizedBox(height: 8),
          if (clampedStops == 0)
            const SizedBox.shrink()
          else
            ...List.generate(clampedStops, (i) {
              return Column(
                children: [
                  _diamondNumber(context, i + 1),
                  const SizedBox(height: 8),
                  const _DottedLine(height: 16),
                  const SizedBox(height: 8),
                ],
              );
            }),
          _dot(context, color: const Color(0xFFEF4444), filled: false),
        ],
      ),
    );
  }

  Widget _dot(BuildContext context, {required Color color, required bool filled}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: filled ? color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 3),
      ),
    );
  }

  Widget _diamondNumber(BuildContext context, int number) {
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        children: [
          Positioned.fill(
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticRow extends StatelessWidget {
  const _StaticRow({required this.text, required this.textStyle});

  final String text;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: textStyle),
      ),
    );
  }
}

class _DottedLine extends StatelessWidget {
  const _DottedLine({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: 20,
      child: CustomPaint(
        painter: _DottedLinePainter(color: const Color(0xFF94A3B8)),
      ),
    );
  }
}

class _DottedLinePainter extends CustomPainter {
  const _DottedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 4.0;
    const dashSpace = 4.0;

    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, startY),
        Offset(size.width / 2, startY + dashHeight),
        paint,
      );
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedLinePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

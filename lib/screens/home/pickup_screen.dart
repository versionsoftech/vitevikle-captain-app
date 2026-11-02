import 'package:flutter/material.dart';
import 'package:vite_captain/screens/home/select_on_map_screen.dart';

class PickupScreen extends StatefulWidget {
  const PickupScreen({
    super.key,
    this.initialPickup,
    this.initialDrop,
  });

  final String? initialPickup;
  final String? initialDrop;

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  final List<TextEditingController> _stopControllers = <TextEditingController>[];

  bool _showTooltip = true;

  @override
  void initState() {
    super.initState();
    _pickupController.text = widget.initialPickup ?? '';
    _dropController.text = widget.initialDrop ?? '';
  }

  @override
  void dispose() {
    for (final c in _stopControllers) {
      c.dispose();
    }
    _pickupController.dispose();
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
    final bg = const Color(0xFFF2F3F5);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Pickup'),
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
              padding: const EdgeInsets.all(16),
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
                            SizedBox(
                              height: 48,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _pickupController.text.trim().isEmpty
                                      ? 'Your Current Location'
                                      : _pickupController.text.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFFE5E7EB),
                            ),
                            ...List.generate(_stopControllers.length, (index) {
                              return Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.onSurface,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: TextField(
                                          controller: _stopControllers[index],
                                          decoration: const InputDecoration(
                                            hintText: 'Add Stop',
                                            border: InputBorder.none,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _removeStop(index),
                                        icon: Icon(
                                          Icons.close,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Color(0xFFE5E7EB),
                                  ),
                                ],
                              );
                            }),
                            TextField(
                              controller: _dropController,
                              decoration: const InputDecoration(
                                hintText: 'Drop location',
                                border: InputBorder.none,
                              ),
                              textInputAction: TextInputAction.done,
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
                        onPressed: () async {
                          final result =
                              await Navigator.push<Map<String, dynamic>>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SelectOnMapScreen(),
                            ),
                          );

                          if (result == null) return;

                          final address = (result['address'] ?? '').toString();
                          if (address.trim().isNotEmpty) {
                            setState(() {
                              _dropController.text = address;
                            });
                          }

                          if (!mounted) return;
                          Navigator.pop(context, result);
                        },
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
                        height: 150,
                        width: 190,
                        child: Image.asset(
                          'assets/images/search_location_illustration.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.search_off,
                                size: 86,
                                color: Color(0xFFCBD5E1),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Could not get address',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please try searching for alternate locations',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_showTooltip)
              Positioned(
                top: 14,
                right: 16,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 230),
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E77FF),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: Text(
                            'You can now book a ride for someone else',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showTooltip = false;
                            });
                          },
                          child: const Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                      ],
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
    final int count = stopsCount < 0 ? 0 : stopsCount;

    return SizedBox(
      width: 18,
      child: Column(
        children: [
          _dot(context, color: const Color(0xFF009640)),
          const SizedBox(height: 6),
          const _DottedLine(height: 22),
          const SizedBox(height: 6),
          ...List.generate(count, (_) {
            return Column(
              children: const [
                SizedBox(height: 24),
                SizedBox(height: 6),
                _DottedLine(height: 18),
                SizedBox(height: 6),
              ],
            );
          }),
          _dot(context, color: const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  Widget _dot(BuildContext context, {required Color color}) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 3),
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
  final Color color;

  const _DottedLinePainter({required this.color});

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


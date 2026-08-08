import 'package:flutter/material.dart';
import 'package:vite_captain/modules/registration/personal_picture_camera_screen.dart';

class PersonalPictureGuideScreen extends StatelessWidget {
  const PersonalPictureGuideScreen({
    super.key,
    required this.driverId,
    required this.mobile,
  });

  final String driverId;
  final String mobile;

  static const Color _green = Color(0xFF369D01);
  static const Color _lightGreen = Color(0xFFB7E11A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text(
          'Personal picture',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _instructionRow('Take a clear picture in good light with clothes on'),
              const SizedBox(height: 10),
              _instructionRow('No filters, sunglasses, or masks'),
              const SizedBox(height: 22),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F7F9),
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: CustomPaint(
                              painter: _CornerFramePainter(color: _green, strokeWidth: 5),
                              child: Center(
                                child: Icon(
                                  Icons.person_outline,
                                  size: 160,
                                  color: Colors.black.withOpacity(0.55),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _lightGreen,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PersonalPictureCameraScreen(
                          driverId: driverId,
                          mobile: mobile,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Take a picture',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instructionRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check, color: _green, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}

class _CornerFramePainter extends CustomPainter {
  _CornerFramePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 32.0;
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(18),
    );

    final left = r.left;
    final top = r.top;
    final right = r.right;
    final bottom = r.bottom;

    canvas.drawLine(Offset(left, top + corner), Offset(left, top), paint);
    canvas.drawLine(Offset(left, top), Offset(left + corner, top), paint);

    canvas.drawLine(Offset(right - corner, top), Offset(right, top), paint);
    canvas.drawLine(Offset(right, top), Offset(right, top + corner), paint);

    canvas.drawLine(Offset(left, bottom - corner), Offset(left, bottom), paint);
    canvas.drawLine(Offset(left, bottom), Offset(left + corner, bottom), paint);

    canvas.drawLine(Offset(right - corner, bottom), Offset(right, bottom), paint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - corner), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


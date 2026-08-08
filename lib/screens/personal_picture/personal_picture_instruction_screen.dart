import 'package:flutter/material.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/screens/personal_picture/selfie_capture_screen.dart';

class PersonalPictureInstructionScreen extends StatefulWidget {
  const PersonalPictureInstructionScreen({super.key});

  @override
  State<PersonalPictureInstructionScreen> createState() => _PersonalPictureInstructionScreenState();
}

class _PersonalPictureInstructionScreenState extends State<PersonalPictureInstructionScreen> {
  static const Color _green = Color(0xFF369D01);
  static const Color _lightGreen = Color(0xFFB7E11A);

  static const SessionService _session = SessionService();

  bool _locked = false;
  String _serverImageUrl = '';

  @override
  void initState() {
    super.initState();
    _hydrateLock();
  }

  Future<void> _hydrateLock() async {
    final basics = await _session.getUserBasics(forceRefresh: true);
    final url = (basics['imageUrl'] ?? '').trim();

    try {
      print('Profile Photo (basics imageUrl): $url');
    } catch (_) {}

    final lowered = url.toLowerCase();
    final hasPhoto = url.isNotEmpty && lowered != 'null' && lowered != 'undefined' && lowered != 'none';
    if (url.isNotEmpty) {
      await _session.saveProfileImageUrl(url);
    }
    if (!mounted) return;
    setState(() {
      _locked = hasPhoto;
      _serverImageUrl = hasPhoto ? url : '';
    });
  }

  Future<void> _capturePhoto() async {
    if (_locked) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SelfieCaptureScreen()),
    );
    await _hydrateLock();
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          title: const Text(
            'Upload Your Profile Photo',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          actions: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upload Your Profile Photo',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87),
                ),
                const SizedBox(height: 6),
                Text(
                  'Profile photo has been verified',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipOval(
                          child: _serverImageUrl.isNotEmpty
                              ? Image.network(
                                  _serverImageUrl,
                                  key: ValueKey(_serverImageUrl),
                                  width: 150,
                                  height: 150,
                                  fit: BoxFit.cover,
                                  headers: const {'Cache-Control': 'no-cache'},
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 150,
                                      height: 150,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.person, color: Colors.grey, size: 70),
                                    );
                                  },
                                )
                              : Container(
                                  width: 150,
                                  height: 150,
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.person, color: Colors.grey, size: 70),
                                ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _green.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Profile Photo Verified',
                            style: TextStyle(color: _green, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: const Text(
          'Upload Your Profile Photo',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upload Your Profile Photo',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87),
              ),
              const SizedBox(height: 6),
              Text(
                'Help us verify your identity quickly',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              _instructionRow('Face clearly visible and centered'),
              const SizedBox(height: 10),
              _instructionRow('Good lighting (avoid dark or blurry photos)'),
              const SizedBox(height: 10),
              _instructionRow('No sunglasses, masks, or filters'),
              const SizedBox(height: 10),
              _instructionRow('Plain background preferred'),
              const SizedBox(height: 18),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: _capturePhoto,
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFFEFFAF2),
                                    Colors.white,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _DashedRRectPainter(color: _green.withOpacity(0.55), strokeWidth: 2, gap: 6),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Container(color: Colors.transparent),
                                    ),
                                    Align(
                                      alignment: Alignment.center,
                                      child: Container(
                                        width: 190,
                                        height: 190,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _green.withOpacity(0.25),
                                            width: 2,
                                            style: BorderStyle.solid,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.person_outline, size: 88, color: Colors.grey.shade400),
                                          const SizedBox(height: 10),
                                          Icon(Icons.camera_alt_outlined, size: 30, color: _green.withOpacity(0.8)),
                                          const SizedBox(height: 10),
                                          Text(
                                            'Tap to capture photo',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_green, _lightGreen],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _capturePhoto,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: Text(
                      _locked ? 'Profile Photo Verified' : 'Capture Photo',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
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
        const Icon(Icons.check_circle_rounded, color: _green, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87, height: 1.25),
          ),
        ),
      ],
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.strokeWidth, required this.gap});

  final Color color;
  final double strokeWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(22),
    );

    final path = Path()..addRRect(r);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final len = gap * 2.2;
        final next = distance + len;
        final extract = metric.extractPath(distance, next);
        canvas.drawPath(extract, paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth || oldDelegate.gap != gap;
  }
}


import 'package:camera/camera.dart';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'package:flutter/material.dart';
import 'package:vite_captain/modules/registration/personal_picture_preview_screen.dart';

class PersonalPictureCameraScreen extends StatefulWidget {
  const PersonalPictureCameraScreen({
    super.key,
    required this.driverId,
    required this.mobile,
  });

  final String driverId;
  final String mobile;

  @override
  State<PersonalPictureCameraScreen> createState() => _PersonalPictureCameraScreenState();
}

class _PersonalPictureCameraScreenState extends State<PersonalPictureCameraScreen> {
  static const Color _green = Color(0xFF009640);

  CameraController? _controller;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initializing = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null) return;

    try {
      final next = _flashOn ? FlashMode.off : FlashMode.torch;
      await c.setFlashMode(next);
      if (!mounted) return;
      setState(() {
        _flashOn = !_flashOn;
      });
    } catch (_) {
      // ignore flash errors for devices that don't support it on front camera
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null) return;
    if (_capturing) return;

    setState(() {
      _capturing = true;
    });

    try {
      final file = await c.takePicture();
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PersonalPicturePreviewScreen(
            driverId: widget.driverId,
            mobile: widget.mobile,
            imagePath: file.path,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _capturing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Personal picture',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        child: _initializing
            ? const Center(child: ViteLoader(color: _green))
            : (_error != null)
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      Positioned.fill(
                        child: CameraPreview(_controller!),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: true,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xAA000000),
                                  Color(0x00000000),
                                  Color(0xAA000000),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 90),
                            child: CustomPaint(
                              painter: _CircleFramePainter(),
                              child: const SizedBox(width: 280, height: 280),
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 118,
                        child: Text(
                          'Adjust the picture to fit in the frame',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 22,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _toggleFlash,
                              icon: Icon(
                                _flashOn ? Icons.flash_on : Icons.flash_off,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 22),
                            GestureDetector(
                              onTap: _capture,
                              child: Container(
                                width: 74,
                                height: 74,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Theme.of(context).colorScheme.surface, width: 4),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 58,
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: _capturing ? Colors.white.withOpacity(0.5) : Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _CircleFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, paint);

    final facePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(w * 0.35, h * 0.38);
    path.quadraticBezierTo(w * 0.50, h * 0.25, w * 0.65, h * 0.38);
    path.quadraticBezierTo(w * 0.72, h * 0.52, w * 0.65, h * 0.68);
    path.quadraticBezierTo(w * 0.50, h * 0.80, w * 0.35, h * 0.68);
    path.quadraticBezierTo(w * 0.28, h * 0.52, w * 0.35, h * 0.38);

    canvas.drawPath(path, facePaint);

    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.33, h * 0.52), width: w * 0.12, height: h * 0.14),
      -1.1,
      2.2,
      false,
      facePaint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.67, h * 0.52), width: w * 0.12, height: h * 0.14),
      2.05,
      2.2,
      false,
      facePaint,
    );

    canvas.drawArc(
      Rect.fromCenter(center: Offset(w * 0.50, h * 0.67), width: w * 0.28, height: h * 0.18),
      0.1,
      2.94,
      false,
      facePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


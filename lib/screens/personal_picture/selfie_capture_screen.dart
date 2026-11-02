import 'dart:async';
import 'package:vite_captain/widgets/vite_loader.dart';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:vite_captain/controllers/profile_controller.dart';
import 'package:vite_captain/services/api_service.dart';
import 'package:vite_captain/services/camera_service.dart';
import 'package:vite_captain/services/face_detector_service.dart';
import 'package:vite_captain/services/dio_client.dart';
import 'package:vite_captain/services/session_service.dart';
import 'package:vite_captain/screens/personal_picture/selfie_preview_screen.dart';

class SelfieCaptureScreen extends StatefulWidget {
  const SelfieCaptureScreen({super.key});

  @override
  State<SelfieCaptureScreen> createState() => _SelfieCaptureScreenState();
}

class _SelfieCaptureScreenState extends State<SelfieCaptureScreen> {
  static const Color _green = Color(0xFF009640);

  final CameraService _cameraService = CameraService();
  final FaceDetectorService _faceService = FaceDetectorService();
  final SessionService _session = const SessionService();

  bool _initializing = true;
  bool _uploading = false;
  bool _locked = false;
  String _message = 'Align your face inside the frame';
  bool _canCapture = false;
  bool _faceInFrame = false;

  DateTime? _validSince;
  String? _lastCapturePath;

  Offset? _lastFaceCenter;
  DateTime? _motionSince;

  Timer? _autoCaptureTimer;
  String? _capturedUrl;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final locked = await _session.getProfileImageLocked();
    final url = (await _session.getProfileImageUrl() ?? '').trim();

    if (!mounted) return;

    if (locked && url.isNotEmpty) {
      setState(() {
        _locked = true;
        _capturedUrl = url;
        _initializing = false;
      });
      return;
    }

    try {
      await _cameraService.initialize(
        resolution: ResolutionPreset.high,
        format: ImageFormatGroup.yuv420,
      );

      if (!mounted) return;
      setState(() {
        _initializing = false;
        _locked = false;
      });

      await _cameraService.startImageStream(_onFrame);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _message = 'Camera error: ${e.toString()}';
      });
    }
  }

  Future<String?> _processCapturedSelfie(String inputPath) async {
    try {
      final faces = await _faceService.detectFacesFromFile(inputPath);
      if (faces.isEmpty) return null;

      // Choose the largest face.
      faces.sort((a, b) =>
          (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
      final face = faces.first;

      final bytes = await File(inputPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      // Normalize orientation so bounding box and pixels are in the same coordinate space.
      final source = img.bakeOrientation(decoded);

      final box = face.boundingBox;
      final cx = box.center.dx;
      final cy = box.center.dy;
      final maxSide = (box.width > box.height ? box.width : box.height);

      // Padding around face.
      final double cropSideD = (maxSide * 1.55).clamp(260.0, 900.0);
      final int cropSide = cropSideD.round();

      int left = (cx - cropSide / 2).round();
      int top = (cy - cropSide / 2).round();

      if (left < 0) left = 0;
      if (top < 0) top = 0;
      if (left + cropSide > source.width) left = (source.width - cropSide).clamp(0, source.width).toInt();
      if (top + cropSide > source.height) top = (source.height - cropSide).clamp(0, source.height).toInt();

      final int safeSide = cropSide
          .clamp(1, (source.width - left).clamp(1, source.width))
          .clamp(1, (source.height - top).clamp(1, source.height));

      final cropped = img.copyCrop(
        source,
        x: left,
        y: top,
        width: safeSide,
        height: safeSide,
      );

      // Resize to a clean profile size.
      final resized = img.copyResize(cropped, width: 512, height: 512, interpolation: img.Interpolation.average);

      // Create circular masked PNG with transparency outside the circle.
      final out = img.Image(width: resized.width, height: resized.height, numChannels: 4);
      final centerX = resized.width / 2.0;
      final centerY = resized.height / 2.0;
      final radius = (resized.width < resized.height ? resized.width : resized.height) / 2.0;
      final radius2 = radius * radius;

      for (int y = 0; y < resized.height; y++) {
        final dy = y - centerY;
        for (int x = 0; x < resized.width; x++) {
          final dx = x - centerX;
          final d2 = dx * dx + dy * dy;
          if (d2 <= radius2) {
            out.setPixel(x, y, resized.getPixel(x, y));
          } else {
            out.setPixelRgba(x, y, 0, 0, 0, 0);
          }
        }
      }

      final dir = await getTemporaryDirectory();
      final outPath = '${dir.path}/selfie_face_${DateTime.now().millisecondsSinceEpoch}.png';
      final png = img.encodePng(out, level: 6);
      await File(outPath).writeAsBytes(png, flush: true);
      return outPath;
    } catch (_) {
      return null;
    }
  }

  InputImageRotation _rotationForMlKit() {
    final c = _cameraService.controller;
    if (c == null) return InputImageRotation.rotation0deg;

    final int sensor = c.description.sensorOrientation;
    final int device = c.value.deviceOrientation == DeviceOrientation.portraitUp
        ? 0
        : c.value.deviceOrientation == DeviceOrientation.landscapeLeft
            ? 90
            : c.value.deviceOrientation == DeviceOrientation.portraitDown
                ? 180
                : 270;

    // Android front camera: rotation = (sensor + device) % 360
    // (Mirror doesn't affect rotation for ML Kit.)
    final int rotation = (sensor + device) % 360;
    switch (rotation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      case 0:
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  bool _isFaceMoving(Face face, int imageWidth, int imageHeight) {
    final center = Offset(
      face.boundingBox.center.dx / imageWidth,
      face.boundingBox.center.dy / imageHeight,
    );

    final last = _lastFaceCenter;
    _lastFaceCenter = center;
    if (last == null) {
      _motionSince = null;
      return true;
    }

    final delta = (center - last).distance;
    // Normalized delta: ~0.02 is small, 0.05+ is significant movement.
    if (delta > 0.055) {
      _motionSince = null;
      return true;
    }

    _motionSince ??= DateTime.now();
    final stillMs = DateTime.now().difference(_motionSince!).inMilliseconds;
    return stillMs < 400;
  }

  Future<void> _onFrame(CameraImage image) async {
    if (!mounted) return;
    if (_uploading || _locked) return;

    final rotation = _rotationForMlKit();
    final faces = await _faceService.detectFaces(image, rotation);

    if (!mounted) return;

    if (faces.isEmpty) {
      _setValidation(valid: false, msg: 'Face not detected');
      _validSince = null;
      _lastFaceCenter = null;
      _motionSince = null;
      if (_faceInFrame) {
        setState(() => _faceInFrame = false);
      }
      return;
    }

    final face = faces.first;
    final inFrame = _faceService.isFaceInFrame(
      face: face,
      imageWidth: image.width,
      imageHeight: image.height,
    );
    if (inFrame != _faceInFrame) {
      setState(() => _faceInFrame = inFrame);
    }

    final brightness = _faceService.estimateBrightness(image);
    final result = _faceService.validate(
      face: face,
      imageWidth: image.width,
      imageHeight: image.height,
      brightness: brightness,
    );

    if (result.isValid) {
      final moving = _isFaceMoving(face, image.width, image.height);
      if (moving) {
        _setValidation(valid: false, msg: 'Hold still');
        _validSince = null;
        _autoCaptureTimer?.cancel();
        return;
      }
    }

    _setValidation(valid: result.isValid, msg: result.message);

    if (result.isValid) {
      _validSince ??= DateTime.now();
      _scheduleAutoCapture();
    } else {
      _validSince = null;
      _autoCaptureTimer?.cancel();
    }
  }

  void _setValidation({required bool valid, required String msg}) {
    if (_canCapture == valid && _message == msg) return;
    setState(() {
      _canCapture = valid;
      _message = msg;
    });
  }

  void _scheduleAutoCapture() {
    if (_autoCaptureTimer != null) return;
    _autoCaptureTimer = Timer(const Duration(milliseconds: 300), () {
      _autoCaptureTimer = null;
      if (!mounted) return;
      final since = _validSince;
      if (since == null) return;
      if (DateTime.now().difference(since).inMilliseconds < 1000) {
        _scheduleAutoCapture();
        return;
      }
      if (_canCapture && !_uploading && !_locked) {
        _captureThenPreview();
      }
    });
  }

  Future<void> _captureThenPreview() async {
    if (_uploading || _locked) return;

    setState(() {
      _uploading = true;
      _message = 'Capturing...';
    });

    try {
      await _cameraService.stopImageStream();

      SystemSound.play(SystemSoundType.click);

      final xfile = await _cameraService.takePicture();

      final processedPath = await _processCapturedSelfie(xfile.path);
      if (processedPath == null) {
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _message = 'Face not detected. Retake.';
        });
        await _cameraService.startImageStream(_onFrame);
        return;
      }

      _lastCapturePath = processedPath;
      if (!mounted) return;

      final confirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => SelfiePreviewScreen(imagePath: processedPath),
        ),
      );

      if (!mounted) return;

      if (confirmed == true) {
        await _uploadLastCapture();
        return;
      }

      // Retake
      _validSince = null;
      _lastFaceCenter = null;
      _motionSince = null;
      setState(() {
        _uploading = false;
        _message = 'Align your face inside the frame';
      });
      await _cameraService.startImageStream(_onFrame);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _message = 'Failed. Tap retry.';
      });
      try {
        await _cameraService.startImageStream(_onFrame);
      } catch (_) {}
    }
  }

  Future<void> _uploadLastCapture() async {
    final path = (_lastCapturePath ?? '').trim();
    if (path.isEmpty) return;

    setState(() {
      _uploading = true;
      _message = 'Uploading...';
    });

    final token = (await _session.getToken() ?? '').trim();
    final driverId = (await _session.getDriverId() ?? '').trim();
    if (token.isEmpty || driverId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _message = 'Unauthorized';
      });
      await _cameraService.startImageStream(_onFrame);
      return;
    }

    final file = File(path);
    if (!file.existsSync()) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _message = 'Captured file not found';
      });
      await _cameraService.startImageStream(_onFrame);
      return;
    }

    final uri = Uri.parse('$baseUrl/driver/upload-profile-image');
    final res = await DioClient.dio.post(
      uri.toString(),
      data: FormData.fromMap({
        'driver_id': driverId,
        'image': await MultipartFile.fromFile(file.path),
      }),
      options: Options(
        validateStatus: (_) => true,
        contentType: Headers.multipartFormDataContentType,
        headers: {
          'Authorization': 'Bearer $token',
        },
      ),
    );

    dynamic decoded;
    try {
      decoded = res.data;
      if (decoded is String) decoded = jsonDecode(decoded);
    } catch (_) {
      decoded = null;
    }

    if (!mounted) return;

    final statusCode = res.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      final msg = (decoded is Map<String, dynamic>)
          ? (decoded['message'] ?? 'Upload failed').toString()
          : 'Upload failed';
      setState(() {
        _uploading = false;
        _message = msg;
      });
      await _cameraService.startImageStream(_onFrame);
      return;
    }

    final imageUrl = (decoded is Map<String, dynamic>)
        ? (decoded['image_url'] ?? decoded['imageUrl'] ?? '').toString().trim()
        : '';

    if (imageUrl.isNotEmpty) {
      await _session.saveProfileImageUrl(imageUrl);
    }
    await _session.saveProfileImageLocked(true);
    ProfileController.clearProfileImage();

    setState(() {
      _uploading = false;
      _locked = true;
      _capturedUrl = imageUrl;
      _message = 'Profile Photo Verified';
    });
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _faceService.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  Widget _readonlyCard() {
    final url = (_capturedUrl ?? '').trim();

    return Column(
      children: [
        const SizedBox(height: 18),
        Center(
          child: ClipOval(
            child: url.isNotEmpty
                ? Image.network(
                    url,
                    key: ValueKey(url),
                    width: 150,
                    height: 150,
                    fit: BoxFit.cover,
                    headers: const {'Cache-Control': 'no-cache'},
                    errorBuilder: (context, error, stack) {
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
    );
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
          'Profile Selfie',
          style: TextStyle(fontWeight: FontWeight.w900),
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
            : _locked
                ? _readonlyCard()
                : (_cameraService.controller == null)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            _message,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: CameraPreview(_cameraService.controller!),
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
                                      Color(0x22000000),
                                      Color(0xCC000000),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 100),
                                child: CustomPaint(
                                  painter: _OvalFramePainter(
                                    color: _canCapture ? _green : Colors.white,
                                  ),
                                  child: const SizedBox(width: 280, height: 360),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 18,
                            right: 18,
                            bottom: 140,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _canCapture ? Icons.check_circle : Icons.info_outline,
                                    color: _canCapture ? _green : Colors.white,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _message,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 18,
                            right: 18,
                            bottom: 40,
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: (!_uploading && !_locked)
                                    ? () {
                                        _validSince = null;
                                        _autoCaptureTimer?.cancel();
                                        _captureThenPreview();
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _green,
                                  disabledBackgroundColor: Colors.white.withOpacity(0.18),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  'Capture',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                ),
                              ),
                            ),
                          ),
                          if (_uploading)
                            const Positioned(
                              left: 0,
                              right: 0,
                              bottom: 100,
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: ViteLoader(strokeWidth: 2.6, color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }
}

class _OvalFramePainter extends CustomPainter {
  _OvalFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width,
      height: size.height,
    );

    final overlay = Paint()..color = Colors.black.withOpacity(0.35);
    final cutout = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final oval = Path()..addOval(rect.deflate(14));
    final combined = Path.combine(PathOperation.difference, cutout, oval);
    canvas.drawPath(combined, overlay);

    final border = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawOval(rect.deflate(14), border);
  }

  @override
  bool shouldRepaint(covariant _OvalFramePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}


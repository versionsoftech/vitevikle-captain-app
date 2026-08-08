import 'dart:async';
import 'package:camera/camera.dart';

class CameraService {
  CameraService();

  CameraController? _controller;
  CameraDescription? _frontCamera;

  CameraController? get controller => _controller;
  CameraDescription? get frontCamera => _frontCamera;

  Future<void> initialize({
    ResolutionPreset resolution = ResolutionPreset.high,
    ImageFormatGroup format = ImageFormatGroup.yuv420,
  }) async {
    final cameras = await availableCameras();
    _frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );

    final controller = CameraController(
      _frontCamera!,
      resolution,
      enableAudio: false,
      imageFormatGroup: format,
    );

    await controller.initialize();
    await controller.setFlashMode(FlashMode.off);
    _controller = controller;
  }

  Future<void> startImageStream(void Function(CameraImage image) onFrame) async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isStreamingImages) return;
    await c.startImageStream(onFrame);
  }

  Future<void> stopImageStream() async {
    final c = _controller;
    if (c == null) return;
    if (!c.value.isStreamingImages) return;
    await c.stopImageStream();
  }

  Future<XFile> takePicture() async {
    final c = _controller;
    if (c == null) {
      throw StateError('Camera not initialized');
    }
    if (c.value.isTakingPicture) {
      throw StateError('Capture in progress');
    }
    return c.takePicture();
  }

  int get sensorOrientation => _frontCamera?.sensorOrientation ?? 0;

  Future<void> dispose() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      if (c.value.isStreamingImages) {
        await c.stopImageStream();
      }
      await c.dispose();
    }
  }
}

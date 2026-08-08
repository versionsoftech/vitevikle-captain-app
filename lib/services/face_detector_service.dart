import 'dart:typed_data';
import 'dart:ui';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class SelfieValidationResult {
  const SelfieValidationResult({
    required this.isValid,
    required this.message,
    this.face,
  });

  final bool isValid;
  final String message;
  final Face? face;
}

class FaceDetectorService {
  FaceDetectorService({FaceDetector? faceDetector})
      : _faceDetector = faceDetector ??
            FaceDetector(
              options: FaceDetectorOptions(
                enableClassification: true,
                enableLandmarks: true,
                enableContours: true,
                enableTracking: false,
                minFaceSize: 0.12,
                performanceMode: FaceDetectorMode.accurate,
              ),
            );

  final FaceDetector _faceDetector;

  bool _busy = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  Uint8List _yuv420ToNv21(CameraImage image) {
    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    final int width = image.width;
    final int height = image.height;

    final Uint8List out = Uint8List(width * height + (width * height ~/ 2));
    int outIndex = 0;

    // Copy Y.
    for (int row = 0; row < height; row++) {
      final int rowStart = row * yPlane.bytesPerRow;
      out.setRange(outIndex, outIndex + width, yPlane.bytes, rowStart);
      outIndex += width;
    }

    // Interleave V and U (NV21 = VU VU ...).
    final int chromaHeight = height ~/ 2;
    final int chromaWidth = width ~/ 2;
    for (int row = 0; row < chromaHeight; row++) {
      final int uRowStart = row * uPlane.bytesPerRow;
      final int vRowStart = row * vPlane.bytesPerRow;
      for (int col = 0; col < chromaWidth; col++) {
        final int uIndex = uRowStart + col * uPlane.bytesPerPixel!;
        final int vIndex = vRowStart + col * vPlane.bytesPerPixel!;
        out[outIndex++] = vPlane.bytes[vIndex];
        out[outIndex++] = uPlane.bytes[uIndex];
      }
    }

    return out;
  }

  Future<List<Face>> detectFacesFromFile(String filePath) async {
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      return _faceDetector.processImage(inputImage);
    } catch (_) {
      return const <Face>[];
    }
  }

  Uint8List _yuv420ToNv21SwapUv(CameraImage image) {
    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    final int width = image.width;
    final int height = image.height;

    final Uint8List out = Uint8List(width * height + (width * height ~/ 2));
    int outIndex = 0;

    for (int row = 0; row < height; row++) {
      final int rowStart = row * yPlane.bytesPerRow;
      out.setRange(outIndex, outIndex + width, yPlane.bytes, rowStart);
      outIndex += width;
    }

    final int chromaHeight = height ~/ 2;
    final int chromaWidth = width ~/ 2;
    for (int row = 0; row < chromaHeight; row++) {
      final int uRowStart = row * uPlane.bytesPerRow;
      final int vRowStart = row * vPlane.bytesPerRow;
      for (int col = 0; col < chromaWidth; col++) {
        final int uIndex = uRowStart + col * uPlane.bytesPerPixel!;
        final int vIndex = vRowStart + col * vPlane.bytesPerPixel!;
        // Swap order (UV instead of VU)
        out[outIndex++] = uPlane.bytes[uIndex];
        out[outIndex++] = vPlane.bytes[vIndex];
      }
    }

    return out;
  }

  Future<List<Face>> _processBytes({
    required Uint8List bytes,
    required Size size,
    required InputImageRotation rotation,
    required InputImageFormat format,
    required int bytesPerRow,
  }) {
    final inputImageData = InputImageMetadata(
      size: size,
      rotation: rotation,
      format: format,
      bytesPerRow: bytesPerRow,
    );

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageData,
    );

    return _faceDetector.processImage(inputImage);
  }

  bool isFaceInFrame({
    required Face face,
    required int imageWidth,
    required int imageHeight,
  }) {
    final box = face.boundingBox;
    final cx = box.center.dx / imageWidth;
    final cy = box.center.dy / imageHeight;
    final centered = (cx - 0.5).abs() < 0.22 && (cy - 0.46).abs() < 0.28;
    if (!centered) return false;

    final areaRatio = (box.width * box.height) / (imageWidth * imageHeight);
    return areaRatio >= 0.055 && areaRatio <= 0.50;
  }

  Future<List<Face>> detectFaces(CameraImage image, InputImageRotation rotation) async {
    if (_busy) return const <Face>[];

    final now = DateTime.now();
    if (now.difference(_lastRun).inMilliseconds < 180) {
      return const <Face>[];
    }

    _busy = true;
    _lastRun = now;

    try {
      final size = Size(image.width.toDouble(), image.height.toDouble());

      Uint8List bytes;
      int bytesPerRow;
      InputImageFormat format;

      if (Platform.isAndroid) {
        // camera plugin typically provides YUV_420_888 (3 planes). ML Kit expects NV21 or YUV.
        // We use NV21 here for maximum compatibility.
        if (image.planes.length == 3) {
          bytes = _yuv420ToNv21(image);
          bytesPerRow = image.width;
          format = InputImageFormat.nv21;
        } else {
          // Fallback: treat as NV21-like single plane.
          final builder = BytesBuilder(copy: false);
          for (final Plane plane in image.planes) {
            builder.add(plane.bytes);
          }
          bytes = builder.toBytes();
          bytesPerRow = image.planes.isNotEmpty ? image.planes.first.bytesPerRow : image.width;
          format = InputImageFormat.nv21;
        }
      } else {
        // iOS typically provides BGRA8888.
        final builder = BytesBuilder(copy: false);
        for (final Plane plane in image.planes) {
          builder.add(plane.bytes);
        }
        bytes = builder.toBytes();
        bytesPerRow = image.planes.isNotEmpty ? image.planes.first.bytesPerRow : image.width;
        format = InputImageFormat.bgra8888;
      }

      var faces = await _processBytes(
        bytes: bytes,
        size: size,
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      );

      if (faces.isNotEmpty) return faces;

      // Android device fallbacks:
      // - Some devices provide U/V planes reversed for the expected NV21 layout
      // - Some devices need a different rotation than what camera reports
      if (Platform.isAndroid && image.planes.length == 3) {
        final swapped = _yuv420ToNv21SwapUv(image);

        final rotationsToTry = <InputImageRotation>[
          InputImageRotation.rotation0deg,
          InputImageRotation.rotation90deg,
          InputImageRotation.rotation270deg,
          InputImageRotation.rotation180deg,
        ];

        // Try same rotation but swapped UV first.
        faces = await _processBytes(
          bytes: swapped,
          size: size,
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        );
        if (faces.isNotEmpty) return faces;

        // Try alternate rotations (both normal and swapped UV).
        for (final r in rotationsToTry) {
          if (r == rotation) continue;
          faces = await _processBytes(
            bytes: bytes,
            size: size,
            rotation: r,
            format: InputImageFormat.nv21,
            bytesPerRow: image.width,
          );
          if (faces.isNotEmpty) return faces;

          faces = await _processBytes(
            bytes: swapped,
            size: size,
            rotation: r,
            format: InputImageFormat.nv21,
            bytesPerRow: image.width,
          );
          if (faces.isNotEmpty) return faces;
        }
      }

      return const <Face>[];
    } finally {
      _busy = false;
    }
  }

  SelfieValidationResult validate({
    required Face face,
    required int imageWidth,
    required int imageHeight,
    required double brightness,
  }) {
    final box = face.boundingBox;

    final cx = box.center.dx / imageWidth;
    final cy = box.center.dy / imageHeight;

    final centered = (cx - 0.5).abs() < 0.22 && (cy - 0.46).abs() < 0.28;
    if (!centered) {
      return const SelfieValidationResult(isValid: false, message: 'Center your face');
    }

    final areaRatio = (box.width * box.height) / (imageWidth * imageHeight);
    if (areaRatio < 0.055) {
      return const SelfieValidationResult(isValid: false, message: 'Move closer');
    }
    if (areaRatio > 0.50) {
      return const SelfieValidationResult(isValid: false, message: 'Move back');
    }

    final roll = (face.headEulerAngleZ ?? 0).abs();
    final yaw = (face.headEulerAngleY ?? 0).abs();
    if (roll > 20 || yaw > 22) {
      return const SelfieValidationResult(isValid: false, message: 'Keep your face straight');
    }

    if (brightness < 0.16) {
      return const SelfieValidationResult(isValid: false, message: 'Improve lighting');
    }

    final leftEye = face.leftEyeOpenProbability;
    final rightEye = face.rightEyeOpenProbability;
    final smile = face.smilingProbability;

    final hasEyes = leftEye != null && rightEye != null;
    if (hasEyes) {
      final eyesOk = leftEye! >= 0.55 && rightEye! >= 0.55;
      if (!eyesOk) {
        if (smile != null && smile >= 0.55) {
          // allow smile as alternative liveness signal
        } else {
          return const SelfieValidationResult(isValid: false, message: 'Blink or smile');
        }
      }
    }

    return SelfieValidationResult(isValid: true, message: 'Perfect! Hold still...', face: face);
  }

  double estimateBrightness(CameraImage image) {
    if (image.planes.isEmpty) return 0.0;
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return 0.0;

    // Sample ~64 pixels for speed.
    final step = (bytes.length ~/ 64).clamp(1, bytes.length);
    int sum = 0;
    int count = 0;
    for (int i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      count++;
      if (count >= 64) break;
    }
    if (count == 0) return 0.0;
    return (sum / count) / 255.0;
  }

  Future<void> dispose() async {
    await _faceDetector.close();
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/face_data.dart';

/// Wraps Google ML Kit face detection with input image conversion utilities.
class FaceDetectorService {
  late final FaceDetector _detector;
  bool _isDisposed = false;

  FaceDetectorService() {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,  // eye open + smiling probabilities
        enableTracking: true,        // stable tracking IDs across frames
        enableLandmarks: false,      // skip — not needed for liveness
        enableContours: false,       // skip — not needed for liveness
        minFaceSize: 0.15,           // ignore very small / background faces
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  /// Processes a camera stream frame and returns detected faces as [FaceData].
  Future<List<FaceData>> processCameraImage(
    CameraImage image,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) async {
    if (_isDisposed) return [];

    try {
      final inputImage = _buildInputImage(image, sensorOrientation, lensDirection);
      if (inputImage == null) return [];

      final faces = await _detector.processImage(inputImage);
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());

      return faces.map((f) => FaceData.fromFace(f, imageSize)).toList();
    } catch (e) {
      debugPrint('[FaceDetectorService] Error: $e');
      return [];
    }
  }

  InputImage? _buildInputImage(
    CameraImage image,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) {
    final rotation = _resolveRotation(sensorOrientation, lensDirection);

    if (Platform.isIOS) {
      // iOS always delivers BGRA8888 as a single plane
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    }

    // Android — convert whatever format the device delivers to NV21.
    // Modern Xiaomi/Pixel/Samsung devices with Camera2 return YUV_420_888
    // (3 planes) even when NV21 is requested. ML Kit only accepts NV21
    // for byte-based InputImage on Android, so we convert unconditionally.
    final nv21Bytes = _toNV21(image);
    if (nv21Bytes == null) return null;

    return InputImage.fromBytes(
      bytes: nv21Bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width, // NV21 stride = width (no padding)
      ),
    );
  }

  /// Converts any camera image format to a flat NV21 byte array.
  ///
  /// NV21 layout: [Y0 Y1 … Yn] [V0 U0 V1 U1 … Vn/4 Un/4]
  /// This correctly handles:
  ///   • YUV_420_888 (3 planes, possibly padded rows)
  ///   • NV21 delivered as single plane (returned as-is)
  ///   • NV12 / other 2-plane layouts
  Uint8List? _toNV21(CameraImage image) {
    try {
      final width = image.width;
      final height = image.height;

      if (image.planes.length == 1) {
        // Already a single-plane NV21 — use directly
        return image.planes[0].bytes;
      }

      final yPlane = image.planes[0];
      final uPlane = image.planes[1]; // U (Cb)
      final vPlane = image.planes[2]; // V (Cr)

      final nv21 = Uint8List(width * height + (width * (height ~/ 2)));
      int idx = 0;

      // --- Y plane (full resolution, strip row padding if any) ---
      final yStride = yPlane.bytesPerRow;
      for (int row = 0; row < height; row++) {
        final start = row * yStride;
        for (int col = 0; col < width; col++) {
          nv21[idx++] = yPlane.bytes[start + col];
        }
      }

      // --- Interleaved VU (half resolution) for NV21 ---
      final uvStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;
      final uvHeight = height ~/ 2;
      final uvWidth = width ~/ 2;

      for (int row = 0; row < uvHeight; row++) {
        for (int col = 0; col < uvWidth; col++) {
          final offset = row * uvStride + col * uvPixelStride;
          nv21[idx++] = vPlane.bytes[offset]; // V first → NV21
          nv21[idx++] = uPlane.bytes[offset]; // U second
        }
      }

      return nv21;
    } catch (e) {
      debugPrint('[FaceDetectorService] NV21 conversion failed: $e');
      return null;
    }
  }

  InputImageRotation _resolveRotation(int sensorOrientation, CameraLensDirection lens) {
    if (Platform.isIOS) return InputImageRotation.rotation0deg;

    // Portrait mode (device held upright, deviceOrientation = 0°):
    //   front camera: (sensorOrientation + 0) % 360 = sensorOrientation
    //   back  camera: (sensorOrientation - 0 + 360) % 360 = sensorOrientation
    // Both are just sensorOrientation — no lens-direction adjustment needed.
    // Source: official google_mlkit_face_detection Flutter example.
    switch (sensorOrientation) {
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  Future<void> dispose() async {
    if (!_isDisposed) {
      _isDisposed = true;
      await _detector.close();
    }
  }
}

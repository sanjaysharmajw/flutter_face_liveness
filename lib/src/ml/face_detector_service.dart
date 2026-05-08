import 'dart:io';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/face_data.dart';
import '../models/frame_quality.dart';
import 'frame_processor.dart';

/// Raw frame metadata forwarded to FaceIdentityService when enableFaceId is on.
class RawFrameData {
  const RawFrameData({
    required this.nv21Bytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.sensorOrientation,
  });
  final Uint8List nv21Bytes;
  final int imageWidth;
  final int imageHeight;
  final int sensorOrientation;
}

/// Result bundle returned per camera frame.
class FaceDetectionResult {
  const FaceDetectionResult({
    required this.faces,
    required this.quality,
    this.rawFrame,
  });

  final List<FaceData> faces;
  final FrameQuality quality;

  /// Present only when [LivenessConfig.enableFaceId] is true.
  final RawFrameData? rawFrame;
}

/// Wraps Google ML Kit face detection.
///
/// Heavy per-frame work (YUV→NV21 conversion + brightness/blur/hash analysis)
/// runs in a background isolate via [FrameProcessor] so the UI thread stays
/// free for 60 fps rendering.
class FaceDetectorService {
  late final FaceDetector _detector;
  bool _isDisposed = false;

  FaceDetectorService() {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        enableLandmarks: false,
        enableContours: false,
        minFaceSize: 0.15,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  /// Process one camera frame.
  ///
  /// Set [captureRawFrame] to `true` (when FaceId is enabled) to attach the
  /// NV21 bytes to the result so the identity service can run the embedding.
  ///
  /// Returns an empty result on error or after dispose.
  Future<FaceDetectionResult> processCameraImage(
    CameraImage image,
    int sensorOrientation,
    CameraLensDirection lensDirection, {
    bool captureRawFrame = false,
  }) async {
    if (_isDisposed) {
      return const FaceDetectionResult(
        faces: [],
        quality: FrameQuality(brightness: 0.5, blurScore: 200, frameHash: 0),
      );
    }

    try {
      // ── Background isolate: YUV conversion + frame quality ───────────────
      final processed = await FrameProcessor.process(image);
      if (processed == null) {
        return const FaceDetectionResult(
          faces: [],
          quality: FrameQuality(brightness: 0.5, blurScore: 200, frameHash: 0),
        );
      }

      // ── Main thread: ML Kit face detection ───────────────────────────────
      final inputImage = _buildInputImage(
        processed.nv21Bytes,
        image,
        sensorOrientation,
        lensDirection,
      );
      if (inputImage == null) {
        return FaceDetectionResult(faces: [], quality: processed.quality);
      }

      final faces = await _detector.processImage(inputImage);
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final faceData = faces
          .map((f) => FaceData.fromFace(f, imageSize))
          .toList();

      final rawFrame = captureRawFrame
          ? RawFrameData(
              nv21Bytes:         processed.nv21Bytes,
              imageWidth:        image.width,
              imageHeight:       image.height,
              sensorOrientation: sensorOrientation,
            )
          : null;

      return FaceDetectionResult(faces: faceData, quality: processed.quality, rawFrame: rawFrame);
    } catch (e) {
      debugPrint('[FaceDetectorService] Error: $e');
      return const FaceDetectionResult(
        faces: [],
        quality: FrameQuality(brightness: 0.5, blurScore: 200, frameHash: 0),
      );
    }
  }

  InputImage? _buildInputImage(
    Uint8List nv21Bytes,
    CameraImage image,
    int sensorOrientation,
    CameraLensDirection lensDirection,
  ) {
    if (Platform.isIOS) {
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

    return InputImage.fromBytes(
      bytes: nv21Bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation(sensorOrientation),
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
  }

  InputImageRotation _rotation(int sensorOrientation) {
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

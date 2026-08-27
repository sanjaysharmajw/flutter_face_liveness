import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

import '../identity/face_preprocessor.dart';
import 'face_detector_service.dart' show RawFrameData;

/// Converts a raw camera frame (NV21 on Android, BGRA8888 on iOS) into an
/// upright JPEG — used to expose a human-viewable capture (e.g.
/// [LivenessResult.bestFrontalImageBytes]) from the same raw bytes the
/// identity pipeline already processes internally, without a second camera
/// capture.
///
/// Returns `null` on decode/encode failure rather than throwing — this is a
/// best-effort convenience feature, never critical-path.
Uint8List? encodeFrameToJpeg(RawFrameData frame, {int quality = 85}) {
  try {
    final w = frame.imageWidth;
    final h = frame.imageHeight;
    final image = img.Image(width: w, height: h);

    if (Platform.isIOS) {
      final bytes = frame.imageBytes;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = (y * w + x) * 4;
          image.setPixelRgb(x, y, bytes[p + 2], bytes[p + 1], bytes[p]); // BGRA → RGB
        }
      }
      // iOS frames are already in display-space orientation (ML Kit is
      // handed rotation0deg — see FaceDetectorService._resolveRotation) —
      // no rotation needed here either.
      return img.encodeJpg(image, quality: quality);
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final rgb = FacePreprocessor.yuv2rgbNv21(frame.imageBytes, x, y, w, h);
        image.setPixelRgb(x, y, rgb[0], rgb[1], rgb[2]);
      }
    }

    // Rotate raw sensor-space pixels to upright. copyRotate's angle is
    // clockwise, but it is NOT simply `sensorOrientation` — 90/270 must be
    // swapped relative to that value. Verified against this file's own
    // already-tested inverse transform (FacePreprocessor._landmarkToSensor,
    // which un-rotates ML Kit's display-space coordinates back to sensor
    // space): composing that inverse with copyRotate's actual per-angle
    // pixel mapping (image package's _rotate90/_rotate270) shows
    // sensorOrientation=90 needs copyRotate(angle: 270) to land upright, and
    // sensorOrientation=270 needs copyRotate(angle: 90) — using
    // sensorOrientation directly (the naive assumption) produces a JPEG
    // rotated 180° off from correct on any device where the front camera's
    // sensorOrientation is 90 or 270 (the common non-zero values).
    final rotateAngle = switch (frame.sensorOrientation) {
      90 => 270,
      270 => 90,
      180 => 180,
      _ => 0,
    };
    final upright = rotateAngle == 0 ? image : img.copyRotate(image, angle: rotateAngle);

    return img.encodeJpg(upright, quality: quality);
  } catch (e) {
    debugPrint('[encodeFrameToJpeg] $e');
    return null;
  }
}

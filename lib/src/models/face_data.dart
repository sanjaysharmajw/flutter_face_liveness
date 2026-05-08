import 'dart:ui' show Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Processed face data extracted from ML Kit detection result.
@immutable
class FaceData {
  const FaceData({
    required this.boundingBox,
    required this.headEulerAngleX,
    required this.headEulerAngleY,
    required this.headEulerAngleZ,
    required this.leftEyeOpenProbability,
    required this.rightEyeOpenProbability,
    required this.smilingProbability,
    required this.trackingId,
    required this.imageSize,
  });

  factory FaceData.fromFace(Face face, Size imageSize) {
    return FaceData(
      boundingBox: face.boundingBox,
      headEulerAngleX: face.headEulerAngleX ?? 0.0,
      headEulerAngleY: face.headEulerAngleY ?? 0.0,
      headEulerAngleZ: face.headEulerAngleZ ?? 0.0,
      leftEyeOpenProbability: face.leftEyeOpenProbability ?? 1.0,
      rightEyeOpenProbability: face.rightEyeOpenProbability ?? 1.0,
      smilingProbability: face.smilingProbability ?? 0.0,
      trackingId: face.trackingId,
      imageSize: imageSize,
    );
  }

  final Rect boundingBox;

  /// Pitch: positive = looking up, negative = looking down
  final double headEulerAngleX;

  /// Yaw: positive = looking right (from viewer's perspective left), negative = looking left
  final double headEulerAngleY;

  /// Roll: head tilt
  final double headEulerAngleZ;

  final double leftEyeOpenProbability;
  final double rightEyeOpenProbability;
  final double smilingProbability;
  final int? trackingId;
  final Size imageSize;

  /// Normalized bounding box relative to image dimensions (0.0 to 1.0)
  Rect get normalizedBoundingBox => Rect.fromLTRB(
        boundingBox.left / imageSize.width,
        boundingBox.top / imageSize.height,
        boundingBox.right / imageSize.width,
        boundingBox.bottom / imageSize.height,
      );

  double get faceAreaRatio {
    final faceArea = boundingBox.width * boundingBox.height;
    final imageArea = imageSize.width * imageSize.height;
    return faceArea / imageArea;
  }

  bool get isFaceTooFar => faceAreaRatio < 0.015;
  bool get isFaceTooClose => faceAreaRatio > 0.70;

  @override
  String toString() => 'FaceData(yaw: ${headEulerAngleY.toStringAsFixed(1)}, '
      'pitch: ${headEulerAngleX.toStringAsFixed(1)}, '
      'leftEye: ${leftEyeOpenProbability.toStringAsFixed(2)}, '
      'rightEye: ${rightEyeOpenProbability.toStringAsFixed(2)})';
}

import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../models/face_detector_backend.dart';
import 'face_identity_service.dart';
import 'yolo_face_detector_service.dart';
import 'scrfd_face_detector_service.dart';

/// Outcome of [FaceCaptureService.captureAndIdentify].
///
/// Distinct from [FaceMatchResult] because a captured photo can be rejected
/// *before* an embedding is ever computed (no face found, image too
/// blurry/dark/small) — those failure modes have no equivalent in the
/// live-frame gallery-matching flow.
@immutable
class FaceCaptureResult {
  const FaceCaptureResult.matched(FaceMatchResult this.match) : rejectionReason = null;
  const FaceCaptureResult.rejected(String this.rejectionReason) : match = null;

  /// Non-null when the capture passed all quality gates and was run through
  /// the identity gallery.
  final FaceMatchResult? match;

  /// Non-null when the capture was rejected before matching — e.g.
  /// "No face detected", "Image too blurry", "Face too small".
  final String? rejectionReason;

  bool get isRejected => rejectionReason != null;
}

/// Orchestrates the "capture a still photo → detect → quality-gate → align →
/// embed → match/register" flow — the counterpart to [LivenessController]'s
/// live-frame identity pipeline, for apps that want enrollment/verification
/// from a single captured picture rather than a full liveness session.
///
/// Composes existing services without duplicating their logic:
/// face detection ([FaceDetectorService]/[YoloFaceDetectorService]/
/// [ScrfdFaceDetectorService] via [FaceDetectorBackend]), alignment
/// ([FacePreprocessor], through [FaceIdentityService.computeEmbeddingFromRgb]),
/// and matching ([FaceIdentityService.identifyFromEmbeddings]).
class FaceCaptureService {
  FaceCaptureService({
    required FaceIdentityService faceIdentity,
    this.backend = FaceDetectorBackend.mlkit,
    this.brightnessMin = 0.12,
    this.brightnessMax = 0.92,
    this.blurThreshold = 80.0,
    this.faceTooFarRatio = 0.015,
    this.faceTooCloseRatio = 0.70,
    this.detectionConfidenceThreshold = 0.5,
  }) : _faceIdentity = faceIdentity;

  final FaceIdentityService _faceIdentity;
  final FaceDetectorBackend backend;

  // ── Pre-capture quality gate (distinct from FaceIdentityService's
  // post-hoc embeddingQuality() check — this rejects before an embedding is
  // even computed) ──────────────────────────────────────────────────────────
  final double brightnessMin;
  final double brightnessMax;
  final double blurThreshold;
  final double faceTooFarRatio;
  final double faceTooCloseRatio;
  final double detectionConfidenceThreshold;

  FaceDetector? _mlkitDetector;
  YoloFaceDetectorService? _yoloDetector;
  ScrfdFaceDetectorService? _scrfdDetector;

  /// Loads the selected detector backend. Call once before [captureAndIdentify].
  /// (ML Kit's detector initialises instantly; YOLOv8/SCRFD download their
  /// model on first use — pass [onYoloModelDownloadProgress] to surface that;
  /// the name predates the [FaceDetectorBackend.scrfd] backend but the
  /// callback applies to whichever non-mlkit backend is selected.)
  ///
  /// A failed YOLOv8/SCRFD download or load is caught and never propagates
  /// out of this method — matching [LivenessController]'s isolation
  /// guarantee for the same models. [captureAndIdentify] reports a clear
  /// rejection reason for that case instead of throwing.
  Future<void> initialize({void Function(double)? onYoloModelDownloadProgress}) async {
    switch (backend) {
      case FaceDetectorBackend.mlkit:
        _mlkitDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: false,
            enableLandmarks: true,
            performanceMode: FaceDetectorMode.accurate, // one-shot, not real-time
          ),
        );
      case FaceDetectorBackend.yolov8:
        try {
          _yoloDetector = YoloFaceDetectorService();
          await _yoloDetector!.load(onProgress: onYoloModelDownloadProgress);
        } catch (e) {
          debugPrint('[FaceCaptureService] YOLOv8 detector unavailable: $e');
          _yoloDetector = null;
        }
      case FaceDetectorBackend.scrfd:
        try {
          _scrfdDetector = ScrfdFaceDetectorService();
          await _scrfdDetector!.load(onProgress: onYoloModelDownloadProgress);
        } catch (e) {
          debugPrint('[FaceCaptureService] SCRFD detector unavailable: $e');
          _scrfdDetector = null;
        }
    }
  }

  /// Runs the full capture → identify pipeline on a photo file (e.g. from
  /// `camera.takePicture()`).
  Future<FaceCaptureResult> captureAndIdentify(
    File imageFile, {
    FaceIdMode? modeOverride,
  }) async {
    final bytes = await imageFile.readAsBytes();
    final rawDecoded = img.decodeImage(bytes);
    if (rawDecoded == null) {
      return const FaceCaptureResult.rejected('Could not decode captured image');
    }
    // Phone camera JPEGs carry an EXIF orientation tag rather than storing
    // pixels upright — decodeImage() does not apply it. ML Kit's
    // InputImage.fromFilePath (used below) DOES honor EXIF orientation, so
    // without baking it here the two coordinate spaces would mismatch for
    // any portrait photo (the common case), and YOLO would detect on a
    // sideways buffer. bakeOrientation() normalises pixel data + width/height
    // to upright once, up front, so everything downstream agrees.
    final decoded = img.bakeOrientation(rawDecoded);

    List<int> samplePixel(int x, int y) {
      final p = decoded.getPixel(
        x.clamp(0, decoded.width - 1),
        y.clamp(0, decoded.height - 1),
      );
      return [p.r.toInt(), p.g.toInt(), p.b.toInt()];
    }

    // ── Detect ──────────────────────────────────────────────────────────
    Rect? bbox;
    double? leftEyeX, leftEyeY, rightEyeX, rightEyeY;

    if (backend == FaceDetectorBackend.yolov8) {
      if (_yoloDetector == null) {
        return const FaceCaptureResult.rejected(
            'YOLOv8 face detector unavailable — model failed to load or download');
      }
      final detections = await _yoloDetector!.detectFromRgbBytes(
        rgbBytes: decoded.getBytes(order: img.ChannelOrder.rgb),
        width: decoded.width,
        height: decoded.height,
        confidenceThreshold: detectionConfidenceThreshold,
      );
      if (detections.isEmpty) {
        return const FaceCaptureResult.rejected('No face detected');
      }
      final best = detections.reduce(
        (a, b) => a.boundingBox.width * a.boundingBox.height >
                   b.boundingBox.width * b.boundingBox.height ? a : b,
      );
      bbox = best.boundingBox;
      leftEyeX = best.leftEye?.dx;   leftEyeY = best.leftEye?.dy;
      rightEyeX = best.rightEye?.dx; rightEyeY = best.rightEye?.dy;
    } else if (backend == FaceDetectorBackend.scrfd) {
      if (_scrfdDetector == null) {
        return const FaceCaptureResult.rejected(
            'SCRFD face detector unavailable — model failed to load or download');
      }
      final detections = await _scrfdDetector!.detectFromRgbBytes(
        rgbBytes: decoded.getBytes(order: img.ChannelOrder.rgb),
        width: decoded.width,
        height: decoded.height,
        confidenceThreshold: detectionConfidenceThreshold,
      );
      if (detections.isEmpty) {
        return const FaceCaptureResult.rejected('No face detected');
      }
      final best = detections.reduce(
        (a, b) => a.boundingBox.width * a.boundingBox.height >
                   b.boundingBox.width * b.boundingBox.height ? a : b,
      );
      bbox = best.boundingBox;
      leftEyeX = best.leftEye.dx;   leftEyeY = best.leftEye.dy;
      rightEyeX = best.rightEye.dx; rightEyeY = best.rightEye.dy;
    } else {
      final detector = _mlkitDetector;
      if (detector == null) {
        return const FaceCaptureResult.rejected('FaceCaptureService not initialized');
      }
      final faces = await detector.processImage(InputImage.fromFilePath(imageFile.path));
      if (faces.isEmpty) {
        return const FaceCaptureResult.rejected('No face detected');
      }
      final best = faces.reduce(
        (a, b) => a.boundingBox.width * a.boundingBox.height >
                   b.boundingBox.width * b.boundingBox.height ? a : b,
      );
      bbox = best.boundingBox;
      leftEyeX = best.landmarks[FaceLandmarkType.leftEye]?.position.x.toDouble();
      leftEyeY = best.landmarks[FaceLandmarkType.leftEye]?.position.y.toDouble();
      rightEyeX = best.landmarks[FaceLandmarkType.rightEye]?.position.x.toDouble();
      rightEyeY = best.landmarks[FaceLandmarkType.rightEye]?.position.y.toDouble();
    }

    // ── Size gate ───────────────────────────────────────────────────────
    final imageArea = decoded.width * decoded.height;
    final faceAreaRatio = (bbox.width * bbox.height) / imageArea;
    if (faceAreaRatio < faceTooFarRatio) {
      return const FaceCaptureResult.rejected('Face too small — move closer');
    }
    if (faceAreaRatio > faceTooCloseRatio) {
      return const FaceCaptureResult.rejected('Face too close — move back');
    }

    // ── Brightness / blur gate ─────────────────────────────────────────
    // Reject before an embedding is computed — distinct from
    // FaceIdentityService.embeddingQuality()'s post-hoc check on the
    // resulting vector.
    final brightness = _meanBrightness(decoded, bbox);
    if (brightness < brightnessMin) {
      return const FaceCaptureResult.rejected('Image too dark');
    }
    if (brightness > brightnessMax) {
      return const FaceCaptureResult.rejected('Image over-exposed');
    }
    final blurScore = _laplacianVariance(decoded, bbox);
    if (blurScore < blurThreshold) {
      return const FaceCaptureResult.rejected('Image too blurry');
    }

    // ── Align + embed ───────────────────────────────────────────────────
    final embedding = await _faceIdentity.computeEmbeddingFromRgb(
      imageWidth: decoded.width,
      imageHeight: decoded.height,
      faceBoundingBox: bbox,
      samplePixel: samplePixel,
      leftEyeX: leftEyeX, leftEyeY: leftEyeY,
      rightEyeX: rightEyeX, rightEyeY: rightEyeY,
    );
    if (embedding == null) {
      return const FaceCaptureResult.rejected('Failed to compute face embedding');
    }

    // ── Match / register (never forces a low-confidence match — see
    // FaceIdentityService.similarityThreshold / FaceIdMode.verificationOnly) ──
    final match = await _faceIdentity.identifyFromEmbeddings(
      [embedding],
      modeOverride: modeOverride,
    );
    if (match == null) {
      return const FaceCaptureResult.rejected('Face matching failed');
    }
    return FaceCaptureResult.matched(match);
  }

  // ── Quality metrics (BT.601 luma, 4-connected Laplacian — same formulas
  // LivenessController already uses for live-frame anti-spoof heuristics,
  // adapted here to package:image's decoded-pixel accessor) ────────────────

  double _meanBrightness(img.Image image, Rect bbox) {
    final x0 = bbox.left.toInt().clamp(0, image.width - 1);
    final y0 = bbox.top.toInt().clamp(0, image.height - 1);
    final x1 = bbox.right.toInt().clamp(x0 + 1, image.width);
    final y1 = bbox.bottom.toInt().clamp(y0 + 1, image.height);

    int sum = 0, count = 0;
    for (int y = y0; y < y1; y += 4) {
      for (int x = x0; x < x1; x += 4) {
        final p = image.getPixel(x, y);
        sum += (77 * p.r.toInt() + 150 * p.g.toInt() + 29 * p.b.toInt()) >> 8;
        count++;
      }
    }
    return count > 0 ? (sum / count) / 255.0 : 0.5;
  }

  double _laplacianVariance(img.Image image, Rect bbox) {
    int luma(int x, int y) {
      final p = image.getPixel(x, y);
      return (77 * p.r.toInt() + 150 * p.g.toInt() + 29 * p.b.toInt()) >> 8;
    }

    final x0 = (bbox.left.toInt() + 1).clamp(1, image.width - 2);
    final y0 = (bbox.top.toInt() + 1).clamp(1, image.height - 2);
    final x1 = (bbox.right.toInt() - 1).clamp(x0, image.width - 1);
    final y1 = (bbox.bottom.toInt() - 1).clamp(y0, image.height - 1);

    double sum = 0.0, sumSq = 0.0;
    int count = 0;
    for (int y = y0; y < y1; y += 3) {
      for (int x = x0; x < x1; x += 3) {
        final lap = (luma(x, y) * 4 - luma(x - 1, y) - luma(x + 1, y) - luma(x, y - 1) - luma(x, y + 1))
            .toDouble();
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }
    if (count < 5) return 0.0;
    final mean = sum / count;
    return sumSq / count - mean * mean;
  }

  Future<void> dispose() async {
    await _mlkitDetector?.close();
    _yoloDetector?.dispose();
    _scrfdDetector?.dispose();
  }
}

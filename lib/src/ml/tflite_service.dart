import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Result from TFLite model inference.
class TFLiteResult {
  const TFLiteResult({
    required this.isReal,
    required this.realScore,
    required this.spoofScore,
  });

  /// True when the model classifies this as a real/live face.
  final bool isReal;

  /// Confidence that input is a real face (0.0–1.0).
  final double realScore;

  /// Confidence that input is a spoofed face (0.0–1.0).
  final double spoofScore;

  @override
  String toString() =>
      'TFLiteResult(real: $isReal, realScore: ${realScore.toStringAsFixed(3)})';
}

/// Service that loads and runs a TensorFlow Lite anti-spoof model.
///
/// ## Setup
/// 1. Obtain or train a binary face anti-spoof model (input: NxN RGB image,
///    output: [real_prob, spoof_prob] softmax).
/// 2. Place the .tflite file in your app's assets/ directory and register it.
/// 3. Pass the asset key or absolute path via [LivenessConfig.tfliteModelPath].
///
/// ## Model contract
/// - Input tensor: [1, inputSize, inputSize, 3] float32 (RGB, 0.0–1.0)
/// - Output tensor: [1, 2] float32 — [real_probability, spoof_probability]
///
/// If the model has a different output shape, override [_parseOutput].
///
/// When [LivenessConfig.enableTFLite] is false this service is never
/// instantiated and adds zero overhead.
class TFLiteService {
  TFLiteService({required this.modelPath, required this.inputSize});

  final String modelPath;
  final int inputSize;

  bool _isLoaded = false;
  Interpreter? _interpreter;

  /// Load the model from [modelPath].
  /// Accepts a Flutter asset key (e.g. `'assets/model.tflite'`) or an
  /// absolute filesystem path (e.g. from `path_provider`).
  /// Call once before [run]. Safe to call multiple times.
  Future<bool> load() async {
    if (_isLoaded) return true;
    try {
      // Absolute path → fromFile (synchronous C binding).
      // Asset key    → fromAsset (async, uses Flutter rootBundle).
      _interpreter = modelPath.startsWith('/')
          ? Interpreter.fromFile(File(modelPath))
          : await Interpreter.fromAsset(modelPath);
      debugPrint('[TFLiteService] TFLite model loaded: $modelPath');
      _isLoaded = true;
      return true;
    } catch (e) {
      debugPrint('[TFLiteService] Failed to load model: $e');
      return false;
    }
  }

  /// Run inference on a camera frame cropped to the detected face.
  ///
  /// [imageBytes]      — NV21 bytes (Android) or BGRA8888 bytes (iOS).
  /// [imageWidth]      — raw frame width.
  /// [imageHeight]     — raw frame height.
  /// [faceBoundingBox] — face rect in ML Kit output space.
  /// [sensorOrientation] — degrees (0, 90, 180, 270) from the camera.
  ///
  /// Returns null when the model is not loaded or inference fails.
  Future<TFLiteResult?> run({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
    required Rect faceBoundingBox,
    required int sensorOrientation,
  }) async {
    if (!_isLoaded || _interpreter == null) return null;
    try {
      final input = _prepareInput(
        imageBytes, imageWidth, imageHeight, faceBoundingBox, sensorOrientation,
      );
      if (input == null) return null;

      // Output: [1, 2] — [real_probability, spoof_probability]
      final outputBuffer = {0: [List.filled(2, 0.0)]};
      _interpreter!.runForMultipleInputs([input], outputBuffer);

      return _parseOutput((outputBuffer[0] as List<List<double>>)[0]);
    } catch (e) {
      debugPrint('[TFLiteService] Inference error: $e');
      return null;
    }
  }

  TFLiteResult _parseOutput(List<double> output) {
    if (output.length < 2) {
      return const TFLiteResult(isReal: true, realScore: 0.5, spoofScore: 0.5);
    }
    final realScore  = output[0].clamp(0.0, 1.0);
    final spoofScore = output[1].clamp(0.0, 1.0);
    return TFLiteResult(
      isReal: realScore > spoofScore,
      realScore: realScore,
      spoofScore: spoofScore,
    );
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }

  // ── Frame preprocessing ─────────────────────────────────────────────────
  // Crops the face bbox from the raw camera frame, resizes to inputSize×inputSize,
  // and normalises pixel values to float32 [0.0, 1.0] for the model input tensor.

  Float32List? _prepareInput(
    Uint8List imageBytes, int imageWidth, int imageHeight,
    Rect faceBoundingBox, int sensorOrientation,
  ) {
    try {
      if (Platform.isIOS) {
        return _fromBgra(imageBytes, imageWidth, imageHeight, faceBoundingBox);
      }
      return _fromNv21(imageBytes, imageWidth, imageHeight, faceBoundingBox, sensorOrientation);
    } catch (e) {
      debugPrint('[TFLiteService] Preprocessing error: $e');
      return null;
    }
  }

  // iOS BGRA8888 — bbox is already in display space
  Float32List _fromBgra(Uint8List bytes, int w, int h, Rect bbox) {
    final r  = _padBbox(bbox, w.toDouble(), h.toDouble());
    final x0 = r.left.toInt().clamp(0, w - 1);
    final y0 = r.top.toInt().clamp(0, h - 1);
    final cw = r.width.toInt().clamp(1, w - x0);
    final ch = r.height.toInt().clamp(1, h - y0);
    final out = Float32List(inputSize * inputSize * 3);
    int i = 0;
    for (int dy = 0; dy < inputSize; dy++) {
      for (int dx = 0; dx < inputSize; dx++) {
        final sx = (x0 + dx * cw ~/ inputSize).clamp(0, w - 1);
        final sy = (y0 + dy * ch ~/ inputSize).clamp(0, h - 1);
        final p  = (sy * w + sx) * 4;
        out[i++] = bytes[p + 2] / 255.0; // R (BGRA → RGB)
        out[i++] = bytes[p + 1] / 255.0; // G
        out[i++] = bytes[p    ] / 255.0; // B
      }
    }
    return out;
  }

  // Android NV21 — bbox is in ML Kit's rotated output space; transform to raw frame space
  Float32List _fromNv21(
    Uint8List nv21, int origW, int origH, Rect rotBbox, int sensorOri,
  ) {
    final origBbox = _bboxToOriginal(rotBbox, origW, origH, sensorOri);
    final x0 = origBbox.left.toInt().clamp(0, origW - 1);
    final y0 = origBbox.top.toInt().clamp(0, origH - 1);
    final cw = origBbox.width.toInt().clamp(1, origW - x0);
    final ch = origBbox.height.toInt().clamp(1, origH - y0);
    final out = Float32List(inputSize * inputSize * 3);
    int i = 0;
    for (int dy = 0; dy < inputSize; dy++) {
      for (int dx = 0; dx < inputSize; dx++) {
        final sx = (x0 + dx * cw ~/ inputSize).clamp(0, origW - 1);
        final sy = (y0 + dy * ch ~/ inputSize).clamp(0, origH - 1);
        final rgb = _yuv2rgb(nv21, sx, sy, origW, origH);
        out[i++] = rgb[0] / 255.0;
        out[i++] = rgb[1] / 255.0;
        out[i++] = rgb[2] / 255.0;
      }
    }
    return out;
  }

  // Reverse the rotation ML Kit applied so the bbox maps back to raw NV21 coords.
  Rect _bboxToOriginal(Rect r, int origW, int origH, int degrees) {
    final double l = r.left, t = r.top, ri = r.right, b = r.bottom;
    late final double nl, nt, nr, nb;
    switch (degrees) {
      case 270:
        nl = t; nt = origH - 1 - ri; nr = b; nb = origH - 1 - l;
      case 90:
        nl = origW - 1 - b; nt = l; nr = origW - 1 - t; nb = ri;
      case 180:
        nl = origW - 1 - ri; nt = origH - 1 - b; nr = origW - 1 - l; nb = origH - 1 - t;
      default:
        nl = l; nt = t; nr = ri; nb = b;
    }
    return _padBbox(Rect.fromLTRB(nl, nt, nr, nb), origW.toDouble(), origH.toDouble());
  }

  Rect _padBbox(Rect box, double maxW, double maxH) {
    final px = box.width  * 0.20;
    final py = box.height * 0.20;
    return Rect.fromLTRB(
      math.max(0, box.left   - px),
      math.max(0, box.top    - py),
      math.min(maxW, box.right  + px),
      math.min(maxH, box.bottom + py),
    );
  }

  // NV21 layout: Y plane [0…w*h), interleaved VU plane [w*h…)
  List<int> _yuv2rgb(Uint8List nv21, int x, int y, int w, int h) {
    final yVal   = nv21[y * w + x] & 0xFF;
    final uvBase = w * h + (y >> 1) * w + (x & ~1);
    final vVal   = nv21[uvBase    ] & 0xFF;
    final uVal   = nv21[uvBase + 1] & 0xFF;
    final r = (yVal + 1.402   * (vVal - 128)).round().clamp(0, 255);
    final g = (yVal - 0.34414 * (uVal - 128) - 0.71414 * (vVal - 128)).round().clamp(0, 255);
    final b = (yVal + 1.772   * (uVal - 128)).round().clamp(0, 255);
    return [r, g, b];
  }
}

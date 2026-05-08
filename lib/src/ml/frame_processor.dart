import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../models/frame_quality.dart';

// ── Isolate-safe data transfer objects ───────────────────────────────────────

class _FrameInput {
  const _FrameInput({
    required this.width,
    required this.height,
    required this.yBytes,
    required this.yStride,
    required this.uBytes,
    required this.uStride,
    required this.uPixelStride,
    required this.vBytes,
    required this.isSinglePlane,
  });

  final int width;
  final int height;
  final Uint8List yBytes;
  final int yStride;
  final Uint8List uBytes;
  final int uStride;
  final int uPixelStride;
  final Uint8List vBytes;
  final bool isSinglePlane;
}

class ProcessedFrame {
  const ProcessedFrame({
    required this.nv21Bytes,
    required this.quality,
  });

  final Uint8List nv21Bytes;
  final FrameQuality quality;
}

// ── Top-level compute() function (runs in a background isolate) ────────────

ProcessedFrame _processFrame(_FrameInput input) {
  final width  = input.width;
  final height = input.height;

  // ── Step 1: Build NV21 bytes ─────────────────────────────────────────────
  Uint8List nv21;

  if (input.isSinglePlane) {
    nv21 = input.yBytes;
  } else {
    nv21 = Uint8List(width * height + width * (height ~/ 2));
    int idx = 0;

    // Y plane — strip row padding
    for (int row = 0; row < height; row++) {
      final start = row * input.yStride;
      for (int col = 0; col < width; col++) {
        nv21[idx++] = input.yBytes[start + col];
      }
    }

    // Interleaved VU (NV21)
    final uvHeight = height ~/ 2;
    final uvWidth  = width  ~/ 2;
    for (int row = 0; row < uvHeight; row++) {
      for (int col = 0; col < uvWidth; col++) {
        final off = row * input.uStride + col * input.uPixelStride;
        nv21[idx++] = input.vBytes[off]; // V first
        nv21[idx++] = input.uBytes[off]; // U second
      }
    }
  }

  // ── Step 2: Compute brightness (average Y) ───────────────────────────────
  // Sub-sample every 8th pixel of the Y-plane for speed.
  final yLen = width * height;
  int ySum = 0;
  int ySamples = 0;
  const yStep = 8;
  for (int i = 0; i < yLen; i += yStep) {
    ySum += nv21[i];
    ySamples++;
  }
  final brightness = (ySamples > 0) ? (ySum / ySamples) / 255.0 : 0.5;

  // ── Step 3: Compute blur score (Y-plane variance on sub-sample) ──────────
  // We compute mean + variance on the same sub-sample.
  double yMean = ySum / ySamples;
  double yVarSum = 0.0;
  for (int i = 0; i < yLen; i += yStep) {
    final diff = nv21[i] - yMean;
    yVarSum += diff * diff;
  }
  final blurScore = ySamples > 0 ? yVarSum / ySamples : 0.0;

  // ── Step 4: Frame hash (FNV-1a on every 16th Y byte) ────────────────────
  int hash = 0x811c9dc5;
  for (int i = 0; i < yLen; i += 16) {
    hash ^= nv21[i];
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }

  return ProcessedFrame(
    nv21Bytes: nv21,
    quality: FrameQuality(
      brightness: brightness,
      blurScore: blurScore,
      frameHash: hash,
    ),
  );
}

// ── Public service ────────────────────────────────────────────────────────────

/// Converts a [CameraImage] to NV21 bytes and computes [FrameQuality] metrics
/// in a background isolate via [compute()], keeping the UI thread free.
class FrameProcessor {
  /// Processes [image] off the main thread.
  /// Returns null if the image format is unsupported or conversion fails.
  static Future<ProcessedFrame?> process(CameraImage image) async {
    try {
      final input = _buildInput(image);
      if (input == null) return null;
      return await compute(_processFrame, input);
    } catch (e) {
      debugPrint('[FrameProcessor] Error: $e');
      return null;
    }
  }

  static _FrameInput? _buildInput(CameraImage image) {
    if (image.planes.isEmpty) return null;

    if (image.planes.length == 1) {
      return _FrameInput(
        width: image.width,
        height: image.height,
        yBytes: image.planes[0].bytes,
        yStride: image.planes[0].bytesPerRow,
        uBytes: Uint8List(0),
        uStride: 0,
        uPixelStride: 1,
        vBytes: Uint8List(0),
        isSinglePlane: true,
      );
    }

    if (image.planes.length < 3) return null;

    return _FrameInput(
      width: image.width,
      height: image.height,
      yBytes: image.planes[0].bytes,
      yStride: image.planes[0].bytesPerRow,
      uBytes: image.planes[1].bytes,
      uStride: image.planes[1].bytesPerRow,
      uPixelStride: image.planes[1].bytesPerPixel ?? 1,
      vBytes: image.planes[2].bytes,
      isSinglePlane: false,
    );
  }
}

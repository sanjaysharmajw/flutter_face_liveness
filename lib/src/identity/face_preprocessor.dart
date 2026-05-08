import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Crops a face region from a raw camera frame and converts it to
/// a 112×112 Float32 RGB tensor (values in [-1, 1]) suitable as
/// MobileFaceNet input.
class FacePreprocessor {
  static const int targetSize = 112;

  /// Returns a [Float32List] of length `112 * 112 * 3`, or `null` on error.
  ///
  /// [imageBytes]  — NV21 bytes (Android) or BGRA8888 bytes (iOS).
  /// [imageWidth]  — original frame width (before any ML Kit rotation).
  /// [imageHeight] — original frame height.
  /// [bbox]        — face bounding box in ML Kit output space (rotated/display).
  /// [sensorOrientation] — degrees (0, 90, 180, 270) as reported by the camera.
  static Float32List? prepare({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
    required Rect bbox,
    required int sensorOrientation,
  }) {
    try {
      if (Platform.isIOS) {
        return _fromBgra(imageBytes, imageWidth, imageHeight, bbox);
      }
      return _fromNv21(imageBytes, imageWidth, imageHeight, bbox, sensorOrientation);
    } catch (e) {
      debugPrint('[FacePreprocessor] $e');
      return null;
    }
  }

  // ── iOS: BGRA8888, bbox already in display space ─────────────────────────

  static Float32List _fromBgra(
    Uint8List bytes, int w, int h, Rect bbox,
  ) {
    final r = _padBbox(bbox, w.toDouble(), h.toDouble());
    return _resampleBgra(bytes, w, r);
  }

  static Float32List _resampleBgra(Uint8List bytes, int w, Rect crop) {
    final out = Float32List(targetSize * targetSize * 3);
    int i = 0;
    final x0 = crop.left.toInt().clamp(0, w - 1);
    final y0 = crop.top.toInt().clamp(0, w - 1);
    final cw = crop.width.toInt().clamp(1, w - x0);
    final ch = crop.height.toInt().clamp(1, w - y0);
    for (int dy = 0; dy < targetSize; dy++) {
      for (int dx = 0; dx < targetSize; dx++) {
        final sx = (x0 + dx * cw ~/ targetSize).clamp(0, w - 1);
        final sy = (y0 + dy * ch ~/ targetSize).clamp(0, w - 1);
        final p  = (sy * w + sx) * 4;
        out[i++] = (bytes[p + 2] / 128.0) - 1.0; // R
        out[i++] = (bytes[p + 1] / 128.0) - 1.0; // G
        out[i++] = (bytes[p    ] / 128.0) - 1.0; // B (BGRA order)
      }
    }
    return out;
  }

  // ── Android: NV21, bbox in rotated (ML Kit display) space ────────────────

  static Float32List _fromNv21(
    Uint8List nv21, int origW, int origH, Rect rotBbox, int sensorOri,
  ) {
    // Transform bbox from ML Kit's rotated output space → original NV21 space
    final origBbox = _bboxToOriginal(rotBbox, origW, origH, sensorOri);
    final x0 = origBbox.left.toInt().clamp(0, origW - 1);
    final y0 = origBbox.top.toInt().clamp(0, origH - 1);
    final cw = origBbox.width.toInt().clamp(1, origW - x0);
    final ch = origBbox.height.toInt().clamp(1, origH - y0);

    final out = Float32List(targetSize * targetSize * 3);
    int i = 0;
    for (int dy = 0; dy < targetSize; dy++) {
      for (int dx = 0; dx < targetSize; dx++) {
        final sx = (x0 + dx * cw ~/ targetSize).clamp(0, origW - 1);
        final sy = (y0 + dy * ch ~/ targetSize).clamp(0, origH - 1);
        final rgb = _yuv2rgb(nv21, sx, sy, origW, origH);
        out[i++] = (rgb[0] / 128.0) - 1.0;
        out[i++] = (rgb[1] / 128.0) - 1.0;
        out[i++] = (rgb[2] / 128.0) - 1.0;
      }
    }
    return out;
  }

  // ── Coordinate transform: rotated ML Kit space → original NV21 space ─────
  //
  // ML Kit rotates the image by `sensorOrientation` degrees CCW before
  // detecting faces, so face bounding boxes are in that rotated space.
  // We reverse the rotation to map them back to the raw NV21 byte layout.

  static Rect _bboxToOriginal(Rect r, int origW, int origH, int degrees) {
    final double l = r.left, t = r.top, ri = r.right, b = r.bottom;
    late final double nl, nt, nr, nb;
    switch (degrees) {
      case 270: // 270° CCW ⟹ (new_x, new_y) = (origH-1-y, x) ⟹ inverse: x=ry, y=origH-1-rx
        nl = t; nt = origH - 1 - ri; nr = b; nb = origH - 1 - l;
        break;
      case 90:  // 90° CCW ⟹ (new_x, new_y) = (y, origW-1-x) ⟹ inverse: x=origW-1-ry, y=rx
        nl = origW - 1 - b; nt = l; nr = origW - 1 - t; nb = ri;
        break;
      case 180:
        nl = origW - 1 - ri; nt = origH - 1 - b; nr = origW - 1 - l; nb = origH - 1 - t;
        break;
      default:
        nl = l; nt = t; nr = ri; nb = b;
    }
    return _padBbox(Rect.fromLTRB(nl, nt, nr, nb), origW.toDouble(), origH.toDouble());
  }

  // 20% padding so the full face (including chin/forehead) is included
  static Rect _padBbox(Rect box, double maxW, double maxH) {
    final px = box.width  * 0.20;
    final py = box.height * 0.20;
    return Rect.fromLTRB(
      math.max(0, box.left   - px),
      math.max(0, box.top    - py),
      math.min(maxW, box.right  + px),
      math.min(maxH, box.bottom + py),
    );
  }

  // ── NV21 → RGB for a single pixel ────────────────────────────────────────
  // NV21 layout (after FrameProcessor strips padding):
  //   Y plane : [0 … w*h)
  //   VU plane: [w*h … w*h + w*h/2)  (V and U interleaved, 2×2 chroma subsampling)

  static List<int> _yuv2rgb(Uint8List nv21, int x, int y, int w, int h) {
    final yVal   = nv21[y * w + x] & 0xFF;
    final uvBase = w * h + (y >> 1) * w + (x & ~1);
    final vVal   = nv21[uvBase    ] & 0xFF;
    final uVal   = nv21[uvBase + 1] & 0xFF;

    final r = (yVal + 1.402  * (vVal - 128)).round().clamp(0, 255);
    final g = (yVal - 0.34414 * (uVal - 128) - 0.71414 * (vVal - 128)).round().clamp(0, 255);
    final b = (yVal + 1.772  * (uVal - 128)).round().clamp(0, 255);
    return [r, g, b];
  }
}

import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show Rect, Offset;

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'face_preprocessor.dart';
import 'scrfd_model_downloader.dart';

/// One detected face from [ScrfdFaceDetectorService].
///
/// Mirrors [YoloFaceDetection]'s shape (bounding box + 5-point keypoints) so
/// it substitutes the same way into the identity pipeline — SCRFD-2.5G-KPS
/// always emits all 5 keypoints (no per-point visibility gating, unlike the
/// YOLOv8-face export), so the keypoint fields here are never null once a
/// detection passes the confidence threshold.
@immutable
class ScrfdFaceDetection {
  const ScrfdFaceDetection({
    required this.boundingBox,
    required this.confidence,
    required this.leftEye,
    required this.rightEye,
    required this.nose,
    required this.mouthLeft,
    required this.mouthRight,
  });

  final Rect boundingBox;
  final double confidence;
  final Offset leftEye;
  final Offset rightEye;
  final Offset nose;
  final Offset mouthLeft;
  final Offset mouthRight;

  bool get hasEyes => true;
}

// ══════════════════════════════════════════════════════════════════════════════
// Isolate message types — plain Dart data only (mirrors YoloFaceDetectorService
// / TFLiteService's pattern). Rect/Offset/ScrfdFaceDetection are NOT sendable
// across the isolate boundary, so results cross the wire as a flat
// List<double> and are reconstructed on the calling isolate.
// ══════════════════════════════════════════════════════════════════════════════

class _InitMsg {
  const _InitMsg(this.modelBytes, this.replyPort);
  final Uint8List modelBytes;
  final SendPort replyPort;
}

class _RunMsg {
  const _RunMsg({
    required this.id,
    required this.imageData,
    required this.imageWidth,
    required this.imageHeight,
    required this.isPrecomputedRgb,
    required this.isIOS,
    required this.confidenceThreshold,
    required this.iouThreshold,
  });
  final int id;
  final TransferableTypedData imageData; // zero-copy transfer
  final int imageWidth, imageHeight;
  final bool isPrecomputedRgb;
  final bool isIOS;
  final double confidenceThreshold;
  final double iouThreshold;
}

// Fields per detection in _ResultMsg.flatDetections:
// [left, top, right, bottom, confidence,
//  leftEyeX, leftEyeY, rightEyeX, rightEyeY,
//  noseX, noseY, mouthLeftX, mouthLeftY, mouthRightX, mouthRightY]
const int _kFieldsPerDetection = 15;

class _ResultMsg {
  const _ResultMsg(this.id, {this.flatDetections, this.error});
  final int id;
  final List<double>? flatDetections;
  final String? error;
}

class _DisposeMsg {
  const _DisposeMsg();
}

// ══════════════════════════════════════════════════════════════════════════════
// SCRFD's 3-stride FPN output layout — auto-detected from the interpreter's
// output tensors at load time (never hardcoded by index): each stride
// contributes a score tensor (C=1), a bbox-distance tensor (C=4) and a
// keypoint-offset tensor (C=10). Detected by classifying every output
// tensor's channel count, then ordering each group by descending anchor
// count (stride 8 always has the most anchors, stride 32 the fewest) — this
// is robust to whatever output ordering the ONNX→TFLite conversion tool used.
// ══════════════════════════════════════════════════════════════════════════════

class _StrideSpec {
  const _StrideSpec({
    required this.stride,
    required this.scoreIdx,
    required this.scoreHasBatchDim,
    required this.bboxIdx,
    required this.bboxHasBatchDim,
    required this.kpsIdx,
    required this.kpsHasBatchDim,
  });
  final int stride;
  final int scoreIdx, bboxIdx, kpsIdx;
  // Each output tensor's batch-dim-ness is tracked independently — a custom
  // (non-bundled) ONNX→TFLite export could in principle mix `[1,N,C]` and
  // `[N,C]` tensors across the 9 outputs, so this must not be collapsed into
  // one shared flag (see load-time classification below).
  final bool scoreHasBatchDim, bboxHasBatchDim, kpsHasBatchDim;
}

// ── Isolate worker ───────────────────────────────────────────────────────

void _scrfdWorker(_InitMsg init) {
  final receivePort = ReceivePort();
  init.replyPort.send(receivePort.sendPort); // handshake step 1

  Interpreter? interp;
  int inputSize = 640;
  bool inputIsNCHW = false;
  List<_StrideSpec> strideSpecs = const [];

  try {
    interp = Interpreter.fromBuffer(init.modelBytes);
    interp.allocateTensors();

    final inputShape = interp.getInputTensor(0).shape;
    if (inputShape.length == 4) {
      if (inputShape[1] == 3) {
        inputIsNCHW = true;
        inputSize = inputShape[2];
      } else if (inputShape[3] == 3) {
        inputIsNCHW = false;
        inputSize = inputShape[1];
      }
    }

    final outTensors = interp.getOutputTensors();
    if (outTensors.length != 9) {
      throw StateError(
          'Expected 9 SCRFD output tensors (score/bbox/kps × 3 strides), '
          'got ${outTensors.length}');
    }

    final scoreIdxs = <int>[];
    final bboxIdxs = <int>[];
    final kpsIdxs = <int>[];
    // Tracked per tensor, not as one shared flag — see _StrideSpec doc comment.
    final hasBatchDimByIdx = List<bool>.filled(outTensors.length, true);
    for (int i = 0; i < outTensors.length; i++) {
      final shape = outTensors[i].shape;
      hasBatchDimByIdx[i] = shape.length == 3;
      final channels = shape.last;
      if (channels == 1) {
        scoreIdxs.add(i);
      } else if (channels == 4) {
        bboxIdxs.add(i);
      } else if (channels == 10) {
        kpsIdxs.add(i);
      }
    }
    if (scoreIdxs.length != 3 || bboxIdxs.length != 3 || kpsIdxs.length != 3) {
      throw StateError('Unrecognized SCRFD output tensor layout — '
          'score=${scoreIdxs.length} bbox=${bboxIdxs.length} kps=${kpsIdxs.length} '
          '(expected 3/3/3)');
    }

    int anchorsAt(int idx) {
      final shape = outTensors[idx].shape;
      final total = shape.reduce((a, b) => a * b);
      return total ~/ shape.last;
    }

    // Most anchors → smallest stride (8), fewest anchors → largest stride (32).
    scoreIdxs.sort((a, b) => anchorsAt(b).compareTo(anchorsAt(a)));
    bboxIdxs.sort((a, b) => anchorsAt(b).compareTo(anchorsAt(a)));
    kpsIdxs.sort((a, b) => anchorsAt(b).compareTo(anchorsAt(a)));

    const strides = [8, 16, 32];
    strideSpecs = List.generate(
      3,
      (i) => _StrideSpec(
        stride: strides[i],
        scoreIdx: scoreIdxs[i], scoreHasBatchDim: hasBatchDimByIdx[scoreIdxs[i]],
        bboxIdx: bboxIdxs[i],   bboxHasBatchDim:  hasBatchDimByIdx[bboxIdxs[i]],
        kpsIdx: kpsIdxs[i],     kpsHasBatchDim:   hasBatchDimByIdx[kpsIdxs[i]],
      ),
    );

    init.replyPort.send(true); // handshake step 2: ready
  } catch (e) {
    init.replyPort.send('ERROR:$e');
    return;
  }

  receivePort.listen((msg) {
    if (msg is _DisposeMsg) {
      interp?.close();
      receivePort.close();
      return;
    }
    if (msg is! _RunMsg) return;
    try {
      final bytes = msg.imageData.materialize().asUint8List();
      final flat = _runInference(
        interp!, bytes, msg.imageWidth, msg.imageHeight,
        isPrecomputedRgb: msg.isPrecomputedRgb,
        isIOS: msg.isIOS,
        inputSize: inputSize,
        inputIsNCHW: inputIsNCHW,
        strideSpecs: strideSpecs,
        confidenceThreshold: msg.confidenceThreshold,
        iouThreshold: msg.iouThreshold,
      );
      init.replyPort.send(_ResultMsg(msg.id, flatDetections: flat));
    } catch (e) {
      init.replyPort.send(_ResultMsg(msg.id, error: e.toString()));
    }
  });
}

// ── Inference (top-level, isolate-safe) ─────────────────────────────────────

List<double> _runInference(
  Interpreter interp,
  Uint8List bytes,
  int srcW,
  int srcH, {
  required bool isPrecomputedRgb,
  required bool isIOS,
  required int inputSize,
  required bool inputIsNCHW,
  required List<_StrideSpec> strideSpecs,
  required double confidenceThreshold,
  required double iouThreshold,
}) {
  (int, int, int) samplePixel(int x, int y) {
    if (isPrecomputedRgb) {
      final p = (y * srcW + x) * 3;
      return (bytes[p], bytes[p + 1], bytes[p + 2]);
    }
    if (isIOS) {
      final p = (y * srcW + x) * 4;
      return (bytes[p + 2], bytes[p + 1], bytes[p]); // BGRA → RGB
    }
    final rgb = FacePreprocessor.yuv2rgbNv21(bytes, x, y, srcW, srcH);
    return (rgb[0], rgb[1], rgb[2]);
  }

  // ── Resize (preserve aspect ratio), top-left aligned, zero-padded ────────
  // Matches InsightFace's own SCRFD preprocessing exactly (no centering,
  // unlike YOLO's letterbox) — the decode below relies on this: original-
  // image coordinates are recovered by dividing by `scale` alone, no pad
  // offset subtraction needed.
  const double mean = 127.5, std = 128.0;
  final scale = math.min(inputSize / srcW, inputSize / srcH);
  final newW  = (srcW * scale).round();
  final newH  = (srcH * scale).round();

  final grid = List.generate(
    inputSize,
    (y) => List.generate(inputSize, (x) {
      if (x >= newW || y >= newH) {
        const v = (0 - mean) / std;
        return const [v, v, v];
      }
      final srcX = (x / scale).round().clamp(0, srcW - 1);
      final srcY = (y / scale).round().clamp(0, srcH - 1);
      final (r, g, b) = samplePixel(srcX, srcY);
      return [(r - mean) / std, (g - mean) / std, (b - mean) / std];
    }),
  );

  final dynamic input = inputIsNCHW
      ? [List.generate(3, (c) => List.generate(
          inputSize, (y) => List.generate(inputSize, (x) => grid[y][x][c])))]
      : [grid];

  // ── Allocate + run all 9 output tensors in one call ──────────────────────
  final outputs = <int, Object>{};
  final buffers  = <int, dynamic>{};
  for (final spec in strideSpecs) {
    for (final idx in [spec.scoreIdx, spec.bboxIdx, spec.kpsIdx]) {
      if (buffers.containsKey(idx)) continue;
      final shape = interp.getOutputTensor(idx).shape;
      final flatLen = shape.reduce((a, b) => a * b);
      final buf = List.filled(flatLen, 0.0).reshape(shape);
      buffers[idx] = buf;
      outputs[idx] = buf;
    }
  }
  interp.runForMultipleInputs([input], outputs);

  double at(dynamic buf, int anchor, int ch, bool hasBatchDim) => hasBatchDim
      ? (buf[0][anchor][ch] as num).toDouble()
      : (buf[anchor][ch] as num).toDouble();

  final detections = <ScrfdFaceDetection>[];

  for (final spec in strideSpecs) {
    final scoreBuf = buffers[spec.scoreIdx];
    final bboxBuf  = buffers[spec.bboxIdx];
    final kpsBuf   = buffers[spec.kpsIdx];
    final stride   = spec.stride;
    final featSize = inputSize ~/ stride;

    final scoreShape = interp.getOutputTensor(spec.scoreIdx).shape;
    final totalAnchors = scoreShape.reduce((a, b) => a * b) ~/ scoreShape.last;
    final numAnchorsPerCell =
        (totalAnchors / (featSize * featSize)).round().clamp(1, 100);

    int anchorIdx = 0;
    for (int cellY = 0; cellY < featSize; cellY++) {
      for (int cellX = 0; cellX < featSize; cellX++) {
        // No +0.5 cell-center offset — matches InsightFace's own anchor
        // generator (`anchor_centers = grid_coord * stride`).
        final cx = (cellX * stride).toDouble();
        final cy = (cellY * stride).toDouble();

        for (int a = 0; a < numAnchorsPerCell; a++) {
          final score = at(scoreBuf, anchorIdx, 0, spec.scoreHasBatchDim);
          if (score >= confidenceThreshold) {
            final l = at(bboxBuf, anchorIdx, 0, spec.bboxHasBatchDim) * stride;
            final t = at(bboxBuf, anchorIdx, 1, spec.bboxHasBatchDim) * stride;
            final r = at(bboxBuf, anchorIdx, 2, spec.bboxHasBatchDim) * stride;
            final b = at(bboxBuf, anchorIdx, 3, spec.bboxHasBatchDim) * stride;

            final box = Rect.fromLTRB(
              (cx - l) / scale, (cy - t) / scale,
              (cx + r) / scale, (cy + b) / scale,
            ).intersect(Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()));

            if (box.width > 0 && box.height > 0) {
              Offset kp(int i) {
                final dx = at(kpsBuf, anchorIdx, i * 2,     spec.kpsHasBatchDim) * stride;
                final dy = at(kpsBuf, anchorIdx, i * 2 + 1, spec.kpsHasBatchDim) * stride;
                return Offset((cx + dx) / scale, (cy + dy) / scale);
              }

              detections.add(ScrfdFaceDetection(
                boundingBox: box,
                confidence: score,
                leftEye: kp(0),
                rightEye: kp(1),
                nose: kp(2),
                mouthLeft: kp(3),
                mouthRight: kp(4),
              ));
            }
          }
          anchorIdx++;
        }
      }
    }
  }

  final kept = _nms(detections, iouThreshold);

  final flat = <double>[];
  for (final d in kept) {
    flat.addAll([
      d.boundingBox.left, d.boundingBox.top, d.boundingBox.right, d.boundingBox.bottom,
      d.confidence,
      d.leftEye.dx,    d.leftEye.dy,
      d.rightEye.dx,   d.rightEye.dy,
      d.nose.dx,       d.nose.dy,
      d.mouthLeft.dx,  d.mouthLeft.dy,
      d.mouthRight.dx, d.mouthRight.dy,
    ]);
  }
  return flat;
}

/// Standard greedy NMS, sorted by confidence descending.
List<ScrfdFaceDetection> _nms(List<ScrfdFaceDetection> detections, double iouThreshold) {
  final sorted = [...detections]..sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <ScrfdFaceDetection>[];

  for (final d in sorted) {
    final overlaps = kept.any((k) => _iou(k.boundingBox, d.boundingBox) > iouThreshold);
    if (!overlaps) kept.add(d);
  }
  return kept;
}

double _iou(Rect a, Rect b) {
  final inter = a.intersect(b);
  final interArea = (inter.width <= 0 || inter.height <= 0) ? 0.0 : inter.width * inter.height;
  final union = a.width * a.height + b.width * b.height - interArea;
  return union <= 0 ? 0.0 : interArea / union;
}

// ══════════════════════════════════════════════════════════════════════════════
// Public service
// ══════════════════════════════════════════════════════════════════════════════

/// Runs a SCRFD-2.5G-KPS TFLite model in a background isolate.
///
/// All inference and preprocessing happens off the caller's isolate — the
/// camera preview and per-frame liveness processing are never blocked, the
/// same guarantee [YoloFaceDetectorService]/[TFLiteService] make.
///
/// This is a second, opt-in detection backend for the identity/recognition
/// pipeline only (see `FaceDetectorBackend`) — it does not replace ML Kit for
/// liveness actions, which need ML Kit's eye-open/smiling classification.
///
/// Input  : square RGB image, size read from the model at load time
///          (typically 640), normalised as `(pixel - 127.5) / 128.0` —
///          SCRFD's own preprocessing convention (different from YOLO's
///          `pixel / 255`). Layout (NCHW vs NHWC) is detected at load time.
/// Output : SCRFD's native 3-stride FPN layout (strides 8/16/32, 2 anchors
///          per cell, 9 raw tensors: score/bbox-distance/keypoint-offset ×
///          3 strides) — decoded here with FCOS-style distance2bbox and
///          distance2kps math, then NMS.
class ScrfdFaceDetectorService {
  bool         _isLoaded = false;
  Isolate?     _isolate;
  SendPort?    _workerPort;
  ReceivePort? _mainPort;
  int          _nextId = 0;
  final Map<int, Completer<_ResultMsg>> _pending = {};

  bool get isLoaded => _isLoaded;

  /// Downloads the model if needed (via [ScrfdModelDownloader]), then loads it
  /// and spins up the background worker isolate.
  Future<void> load({
    String? modelUrl,
    void Function(double)? onProgress,
  }) async {
    final downloader = ScrfdModelDownloader(modelUrl: modelUrl, onProgress: onProgress);
    final modelPath  = await downloader.ensureModel();

    try {
      final modelBytes = await File(modelPath).readAsBytes();

      _mainPort = ReceivePort();
      var handshakeDone = false;
      final readyCompleter = Completer<bool>();

      _mainPort!.listen((msg) {
        if (!handshakeDone) {
          if (msg is SendPort) {
            _workerPort = msg;
          } else if (msg == true) {
            handshakeDone = true;
            if (!readyCompleter.isCompleted) readyCompleter.complete(true);
          } else if (msg is String && msg.startsWith('ERROR:')) {
            debugPrint('[ScrfdFaceDetectorService] Worker init error: $msg');
            if (!readyCompleter.isCompleted) readyCompleter.complete(false);
          }
        } else {
          if (msg is _ResultMsg) {
            _pending.remove(msg.id)?.complete(msg);
          }
        }
      });

      _isolate = await Isolate.spawn(_scrfdWorker, _InitMsg(modelBytes, _mainPort!.sendPort));

      final ready = await readyCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );

      if (!ready) {
        debugPrint('[ScrfdFaceDetectorService] Worker failed to become ready');
        _disposeWorker();
        throw Exception('[ScrfdFaceDetectorService] Worker init failed');
      }

      _isLoaded = true;
      debugPrint('[ScrfdFaceDetectorService] Worker isolate ready — $modelPath');
    } catch (e) {
      _disposeWorker();
      await ScrfdModelDownloader.clearCache();
      throw Exception('[ScrfdFaceDetectorService] Load failed (cache cleared): $e');
    }
  }

  /// Detects faces in a raw camera frame (NV21 on Android, BGRA8888 on iOS —
  /// matching [RawFrameData]/[FacePreprocessor]'s existing contract).
  ///
  /// Execution is fully off the caller's isolate — calling this never blocks
  /// camera-frame delivery.
  Future<List<ScrfdFaceDetection>> detectFromRawFrame({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
    double confidenceThreshold = 0.5,
    double iouThreshold = 0.45,
  }) => _run(
    imageBytes, imageWidth, imageHeight,
    isPrecomputedRgb: false, isIOS: Platform.isIOS,
    confidenceThreshold: confidenceThreshold, iouThreshold: iouThreshold,
  );

  /// Detects faces in an already-decoded RGB still image (e.g. a captured
  /// photo via [FaceCaptureService]).
  ///
  /// [rgbBytes] must be tightly-packed RGB triples, row-major — e.g.
  /// `decodedImage.getBytes(order: img.ChannelOrder.rgb)` from `package:image`.
  Future<List<ScrfdFaceDetection>> detectFromRgbBytes({
    required Uint8List rgbBytes,
    required int width,
    required int height,
    double confidenceThreshold = 0.5,
    double iouThreshold = 0.45,
  }) => _run(
    rgbBytes, width, height,
    isPrecomputedRgb: true, isIOS: false,
    confidenceThreshold: confidenceThreshold, iouThreshold: iouThreshold,
  );

  Future<List<ScrfdFaceDetection>> _run(
    Uint8List bytes, int width, int height, {
    required bool isPrecomputedRgb,
    required bool isIOS,
    required double confidenceThreshold,
    required double iouThreshold,
  }) async {
    if (!_isLoaded || _workerPort == null) {
      debugPrint('[ScrfdFaceDetectorService] run skipped — not loaded');
      return const [];
    }
    try {
      final id = _nextId++;
      final completer = Completer<_ResultMsg>();
      _pending[id] = completer;

      _workerPort!.send(_RunMsg(
        id: id,
        imageData: TransferableTypedData.fromList([bytes]),
        imageWidth: width, imageHeight: height,
        isPrecomputedRgb: isPrecomputedRgb, isIOS: isIOS,
        confidenceThreshold: confidenceThreshold, iouThreshold: iouThreshold,
      ));

      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _pending.remove(id);
          return _ResultMsg(id, error: 'timeout');
        },
      );

      if (result.error != null) {
        debugPrint('[ScrfdFaceDetectorService] Inference error: ${result.error}');
        return const [];
      }
      return _inflate(result.flatDetections ?? const []);
    } catch (e) {
      debugPrint('[ScrfdFaceDetectorService] run() error: $e');
      return const [];
    }
  }

  List<ScrfdFaceDetection> _inflate(List<double> flat) {
    final out = <ScrfdFaceDetection>[];
    for (int i = 0; i + _kFieldsPerDetection <= flat.length; i += _kFieldsPerDetection) {
      out.add(ScrfdFaceDetection(
        boundingBox: Rect.fromLTRB(flat[i], flat[i + 1], flat[i + 2], flat[i + 3]),
        confidence: flat[i + 4],
        leftEye:    Offset(flat[i + 5],  flat[i + 6]),
        rightEye:   Offset(flat[i + 7],  flat[i + 8]),
        nose:       Offset(flat[i + 9],  flat[i + 10]),
        mouthLeft:  Offset(flat[i + 11], flat[i + 12]),
        mouthRight: Offset(flat[i + 13], flat[i + 14]),
      ));
    }
    return out;
  }

  void dispose() => _disposeWorker();

  void _disposeWorker() {
    _workerPort?.send(const _DisposeMsg());
    _isolate?.kill(priority: Isolate.immediate);
    _mainPort?.close();
    _isolate    = null;
    _workerPort = null;
    _mainPort   = null;
    _isLoaded   = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('ScrfdFaceDetectorService disposed'));
    }
    _pending.clear();
  }
}

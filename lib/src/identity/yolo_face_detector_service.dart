import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show Rect, Offset;

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'face_preprocessor.dart';
import 'yolo_model_downloader.dart';

/// One detected face from [YoloFaceDetectorService].
///
/// Eye/nose/mouth points are populated when the exported model includes the
/// standard 5-point face keypoints (left eye, right eye, nose, mouth-left,
/// mouth-right) — the same layout [FacePreprocessor] already expects for
/// eye-aligned cropping, so a [YoloFaceDetection] can substitute directly for
/// ML Kit's landmarks in the identity pipeline.
@immutable
class YoloFaceDetection {
  const YoloFaceDetection({
    required this.boundingBox,
    required this.confidence,
    this.leftEye,
    this.rightEye,
    this.nose,
    this.mouthLeft,
    this.mouthRight,
  });

  final Rect boundingBox;
  final double confidence;
  final Offset? leftEye;
  final Offset? rightEye;
  final Offset? nose;
  final Offset? mouthLeft;
  final Offset? mouthRight;

  bool get hasEyes => leftEye != null && rightEye != null;
}

// ══════════════════════════════════════════════════════════════════════════════
// Isolate message types — plain Dart data only (mirrors TFLiteService's
// pattern in ../ml/tflite_service.dart). Rect/Offset/YoloFaceDetection are
// NOT sendable across the isolate boundary, so results cross the wire as a
// flat List<double> and are reconstructed on the calling isolate.
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
  // true  → imageData is tightly-packed RGB triples, row-major (a decoded
  //         still photo — see detectFromRgbBytes)
  // false → imageData is raw camera bytes (NV21 on Android, BGRA8888 on iOS)
  final bool isPrecomputedRgb;
  final bool isIOS;
  final double confidenceThreshold;
  final double iouThreshold;
}

// Fields per detection in _ResultMsg.flatDetections:
// [left, top, right, bottom, confidence,
//  leftEyeX, leftEyeY, rightEyeX, rightEyeY,
//  noseX, noseY, mouthLeftX, mouthLeftY, mouthRightX, mouthRightY]
// NaN marks an absent keypoint.
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
// Background isolate worker — owns the Interpreter, never blocks the caller's
// isolate (mirrors TFLiteService._tfliteWorker)
// ══════════════════════════════════════════════════════════════════════════════

void _yoloWorker(_InitMsg init) {
  final receivePort = ReceivePort();
  init.replyPort.send(receivePort.sendPort); // handshake step 1

  Interpreter? interp;
  int inputSize = 320;
  bool inputIsNCHW = false;

  try {
    interp = Interpreter.fromBuffer(init.modelBytes);
    interp.allocateTensors();

    final inputShape = interp.getInputTensor(0).shape;
    if (inputShape.length == 4) {
      if (inputShape[1] == 3) {
        // NCHW: [1, 3, H, W] — litert_torch (PyTorch-native) exports use this.
        inputIsNCHW = true;
        inputSize = inputShape[2];
      } else if (inputShape[3] == 3) {
        // NHWC: [1, H, W, 3] — TensorFlow-native exports use this.
        inputIsNCHW = false;
        inputSize = inputShape[1];
      }
    }
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
  required double confidenceThreshold,
  required double iouThreshold,
}) {
  // Samples the source buffer directly — no rotation applied in any branch,
  // so results land in the same "sensor space" the raw buffer is in (matches
  // the contract FacePreprocessor.prepare(coordinatesInSensorSpace: true)
  // expects for YOLO-sourced coordinates — see LivenessController).
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

  // ── Letterbox resize (preserve aspect ratio, pad with grey 114) ──────────
  final scale = math.min(inputSize / srcW, inputSize / srcH);
  final newW  = (srcW * scale).round();
  final newH  = (srcH * scale).round();
  final padX  = (inputSize - newW) ~/ 2;
  final padY  = (inputSize - newH) ~/ 2;

  final grid = List.generate(
    inputSize,
    (y) => List.generate(inputSize, (x) {
      final srcX = ((x - padX) / scale).round();
      final srcY = ((y - padY) / scale).round();
      if (srcX < 0 || srcX >= srcW || srcY < 0 || srcY >= srcH) {
        return const [114 / 255.0, 114 / 255.0, 114 / 255.0];
      }
      final (r, g, b) = samplePixel(srcX, srcY);
      return [r / 255.0, g / 255.0, b / 255.0];
    }),
  );

  final dynamic input = inputIsNCHW
      // [1, 3, H, W] — channel planes, each H×W
      ? [List.generate(3, (c) => List.generate(
          inputSize, (y) => List.generate(inputSize, (x) => grid[y][x][c])))]
      // [1, H, W, 3] — per-pixel RGB triples
      : [grid];

  final outputShape = interp.getOutputTensor(0).shape; // e.g. [1, 20, N] or [1, N, 20]
  final flatLen = outputShape.reduce((a, b) => a * b);
  final output  = List.filled(flatLen, 0.0).reshape(outputShape);

  interp.run(input, output);

  final detections = _decodeOutput(
    output, outputShape,
    scale: scale, padX: padX.toDouble(), padY: padY.toDouble(),
    srcW: srcW, srcH: srcH,
    confidenceThreshold: confidenceThreshold,
  );
  final kept = _nms(detections, iouThreshold);

  final flat = <double>[];
  for (final d in kept) {
    flat.addAll([
      d.boundingBox.left, d.boundingBox.top, d.boundingBox.right, d.boundingBox.bottom,
      d.confidence,
      d.leftEye?.dx    ?? double.nan, d.leftEye?.dy    ?? double.nan,
      d.rightEye?.dx   ?? double.nan, d.rightEye?.dy   ?? double.nan,
      d.nose?.dx       ?? double.nan, d.nose?.dy       ?? double.nan,
      d.mouthLeft?.dx  ?? double.nan, d.mouthLeft?.dy  ?? double.nan,
      d.mouthRight?.dx ?? double.nan, d.mouthRight?.dy ?? double.nan,
    ]);
  }
  return flat;
}

/// Decodes the raw model output into image-space detections.
///
/// Handles both `[1, C, N]` (channels-first) and `[1, N, C]` (anchors-first)
/// layouts — Ultralytics TFLite exports commonly use the former, but this
/// stays defensive since the exact layout depends on export flags.
List<YoloFaceDetection> _decodeOutput(
  dynamic output,
  List<int> shape, {
  required double scale,
  required double padX,
  required double padY,
  required int srcW,
  required int srcH,
  required double confidenceThreshold,
}) {
  const channels = 20; // 4 box + 1 conf + 5 keypoints * 3
  final dim1 = shape[1], dim2 = shape[2];
  final channelsFirst = dim1 == channels;
  final numAnchors = channelsFirst ? dim2 : dim1;

  double at(int anchor, int ch) =>
      channelsFirst ? (output[0][ch][anchor] as num).toDouble()
                    : (output[0][anchor][ch] as num).toDouble();

  final results = <YoloFaceDetection>[];
  for (int a = 0; a < numAnchors; a++) {
    final conf = at(a, 4);
    if (conf < confidenceThreshold) continue;

    final cx = at(a, 0), cy = at(a, 1), w = at(a, 2), h = at(a, 3);

    Offset? kp(int idx) {
      final x = at(a, 5 + idx * 3);
      final y = at(a, 5 + idx * 3 + 1);
      final vis = at(a, 5 + idx * 3 + 2);
      if (vis < 0.3) return null;
      return Offset((x - padX) / scale, (y - padY) / scale);
    }

    final box = Rect.fromLTWH(
      ((cx - w / 2) - padX) / scale,
      ((cy - h / 2) - padY) / scale,
      w / scale,
      h / scale,
    ).intersect(Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()));

    if (box.width <= 0 || box.height <= 0) continue;

    results.add(YoloFaceDetection(
      boundingBox: box,
      confidence: conf,
      leftEye: kp(0),
      rightEye: kp(1),
      nose: kp(2),
      mouthLeft: kp(3),
      mouthRight: kp(4),
    ));
  }
  return results;
}

/// Standard greedy NMS, sorted by confidence descending.
List<YoloFaceDetection> _nms(List<YoloFaceDetection> detections, double iouThreshold) {
  final sorted = [...detections]..sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <YoloFaceDetection>[];

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

/// Runs a YOLOv8n-face TFLite model in a background isolate.
///
/// All inference and preprocessing happens off the caller's isolate — the
/// camera preview and per-frame liveness processing are never blocked, the
/// same guarantee [TFLiteService] (../ml/tflite_service.dart) makes for the
/// anti-spoof/video-replay models.
///
/// This is a second, opt-in detection backend for the identity/recognition
/// pipeline only (see `FaceDetectorBackend`) — it does not replace ML Kit for
/// liveness actions, which need ML Kit's eye-open/smiling classification.
///
/// Input  : square RGB image, size read from the model at load time
///          (typically 320 or 640), pixel values normalised to [0, 1].
///          Layout (NCHW vs NHWC) is also detected at load time.
/// Output : standard Ultralytics raw pose/keypoint export layout —
///          `[1, 4 + 1 + 5*3, N]` (box xywh + face-confidence + 5 keypoints
///          × (x, y, visibility), N anchors) — decoded here with NMS.
class YoloFaceDetectorService {
  bool         _isLoaded = false;
  Isolate?     _isolate;
  SendPort?    _workerPort;
  ReceivePort? _mainPort;
  int          _nextId = 0;
  final Map<int, Completer<_ResultMsg>> _pending = {};

  bool get isLoaded => _isLoaded;

  /// Downloads the model if needed (via [YoloModelDownloader]), then loads it
  /// and spins up the background worker isolate.
  Future<void> load({
    String? modelUrl,
    void Function(double)? onProgress,
  }) async {
    final downloader = YoloModelDownloader(modelUrl: modelUrl, onProgress: onProgress);
    final modelPath  = await downloader.ensureModel();

    try {
      final modelBytes = await File(modelPath).readAsBytes();

      _mainPort = ReceivePort();
      var handshakeDone = false;
      final readyCompleter = Completer<bool>();

      // Single listener handles both the handshake and ongoing inference results.
      _mainPort!.listen((msg) {
        if (!handshakeDone) {
          if (msg is SendPort) {
            _workerPort = msg;
          } else if (msg == true) {
            handshakeDone = true;
            if (!readyCompleter.isCompleted) readyCompleter.complete(true);
          } else if (msg is String && msg.startsWith('ERROR:')) {
            debugPrint('[YoloFaceDetectorService] Worker init error: $msg');
            if (!readyCompleter.isCompleted) readyCompleter.complete(false);
          }
        } else {
          if (msg is _ResultMsg) {
            _pending.remove(msg.id)?.complete(msg);
          }
        }
      });

      _isolate = await Isolate.spawn(_yoloWorker, _InitMsg(modelBytes, _mainPort!.sendPort));

      final ready = await readyCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );

      if (!ready) {
        debugPrint('[YoloFaceDetectorService] Worker failed to become ready');
        _disposeWorker();
        throw Exception('[YoloFaceDetectorService] Worker init failed');
      }

      _isLoaded = true;
      debugPrint('[YoloFaceDetectorService] Worker isolate ready — $modelPath');
    } catch (e) {
      _disposeWorker();
      await YoloModelDownloader.clearCache();
      throw Exception('[YoloFaceDetectorService] Load failed (cache cleared): $e');
    }
  }

  /// Detects faces in a raw camera frame (NV21 on Android, BGRA8888 on iOS —
  /// matching [RawFrameData]/[FacePreprocessor]'s existing contract).
  ///
  /// Execution is fully off the caller's isolate — calling this never blocks
  /// camera-frame delivery.
  Future<List<YoloFaceDetection>> detectFromRawFrame({
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
  Future<List<YoloFaceDetection>> detectFromRgbBytes({
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

  Future<List<YoloFaceDetection>> _run(
    Uint8List bytes, int width, int height, {
    required bool isPrecomputedRgb,
    required bool isIOS,
    required double confidenceThreshold,
    required double iouThreshold,
  }) async {
    if (!_isLoaded || _workerPort == null) {
      debugPrint('[YoloFaceDetectorService] run skipped — not loaded');
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
        debugPrint('[YoloFaceDetectorService] Inference error: ${result.error}');
        return const [];
      }
      return _inflate(result.flatDetections ?? const []);
    } catch (e) {
      debugPrint('[YoloFaceDetectorService] run() error: $e');
      return const [];
    }
  }

  List<YoloFaceDetection> _inflate(List<double> flat) {
    final out = <YoloFaceDetection>[];
    Offset? pt(double x, double y) => x.isNaN ? null : Offset(x, y);
    for (int i = 0; i + _kFieldsPerDetection <= flat.length; i += _kFieldsPerDetection) {
      out.add(YoloFaceDetection(
        boundingBox: Rect.fromLTRB(flat[i], flat[i + 1], flat[i + 2], flat[i + 3]),
        confidence: flat[i + 4],
        leftEye:    pt(flat[i + 5],  flat[i + 6]),
        rightEye:   pt(flat[i + 7],  flat[i + 8]),
        nose:       pt(flat[i + 9],  flat[i + 10]),
        mouthLeft:  pt(flat[i + 11], flat[i + 12]),
        mouthRight: pt(flat[i + 13], flat[i + 14]),
      ));
    }
    return out;
  }

  void dispose() => _disposeWorker();

  void _disposeWorker() {
    _workerPort?.send(const _DisposeMsg()); // graceful shutdown
    _isolate?.kill(priority: Isolate.immediate);
    _mainPort?.close();
    _isolate    = null;
    _workerPort = null;
    _mainPort   = null;
    _isLoaded   = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('YoloFaceDetectorService disposed'));
    }
    _pending.clear();
  }
}

import 'dart:async' show unawaited;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'models/face_data.dart';
import 'models/liveness_action.dart';
import 'models/liveness_config.dart';
import 'models/liveness_result.dart';
import 'models/detection_status.dart';
import 'models/frame_quality.dart';
import 'camera/camera_service.dart';
import 'ml/face_detector_service.dart';
import 'ml/tflite_service.dart';
import 'ml/tflite_model_downloader.dart';
import 'ml/video_replay_model_downloader.dart';
import 'liveness/liveness_engine.dart';
import 'identity/face_identity_service.dart';

/// ChangeNotifier that drives the full liveness verification session.
///
/// Lifecycle: [initialize] → frames processed automatically → callbacks fired.
class LivenessController extends ChangeNotifier {
  LivenessController({
    required List<LivenessAction> actions,
    required this.onSuccess,
    required this.onFailed,
    LivenessConfig config = const LivenessConfig(),
  })  : _actions = actions,
        _config  = config;

  final List<LivenessAction> _actions;
  final LivenessConfig _config;
  final void Function(LivenessResult result) onSuccess;
  final void Function(String reason)          onFailed;

  final CameraService _cameraService = CameraService();
  final FaceDetectorService _faceDetector = FaceDetectorService();
  TFLiteService?        _tflite;
  TFLiteService?        _videoReplay;
  FaceIdentityService?  _faceIdentity;
  LivenessEngine?       _engine;

  bool _isInitialized = false;
  bool _isDisposed    = false;
  FaceData?      _currentFace;
  FrameQuality?  _lastQuality;
  RawFrameData?  _lastRawFrame;
  String?        _error;
  double?        _faceIdModelDownloadProgress;
  double?        _tfliteModelDownloadProgress;
  String?        _tfliteWarning;
  double?        _lastTfliteScore;
  bool           _isTfliteRunning = false;
  Future<void>?  _tfliteFuture;

  double?        _lastVideoReplayScore;
  bool           _isVideoReplayRunning = false;
  Future<void>?  _videoReplayFuture;

  // ── Public getters ──────────────────────────────────────────────────────
  bool            get isInitialized   => _isInitialized;
  /// True when [LivenessConfig.enableTFLite] is set and the model loaded
  /// successfully. False means [LivenessResult.tfliteScore] will be null.
  bool            get isTFLiteLoaded  => _tflite != null;
  /// Non-null when [enableTFLite] is true but the model could not be loaded
  /// (download failed, model file missing, or corrupted cache).
  String?         get tfliteWarning   => _tfliteWarning;
  /// Non-null (0.0–1.0) while the TFLite anti-spoof model is being downloaded
  /// for the first time. Null when loading from cache or when complete.
  double?         get tfliteModelDownloadProgress => _tfliteModelDownloadProgress;
  /// Non-null (0.0–1.0) while the FaceNet model is being downloaded for the
  /// first time. Null when loading from cache or when download is complete.
  double?         get faceIdModelDownloadProgress => _faceIdModelDownloadProgress;
  FaceData?       get currentFace     => _currentFace;
  FrameQuality?   get lastQuality     => _lastQuality;
  String?         get error           => _error;
  CameraController? get cameraController => _cameraService.controller;

  DetectionStatus get status =>
      _isInitialized ? _engine!.status : DetectionStatus.initializing;
  LivenessAction? get currentAction  =>
      _isInitialized ? _engine!.currentAction : null;
  double  get progress          => _isInitialized ? _engine!.progress             : 0.0;
  int     get completedCount    => _isInitialized ? _engine!.completedActions.length : 0;
  int     get totalActions      => _actions.length;
  bool    get isComplete        => _isInitialized && (_engine?.isComplete ?? false);
  String? get sessionId         => _isInitialized ? _engine!.sessionId           : null;
  LivenessConfig get config     => _config;
  List<LivenessAction> get completedActions =>
      _isInitialized ? _engine!.completedActions : const [];
  List<LivenessAction> get remainingActions =>
      _isInitialized ? _engine!.remainingActions : _actions;

  // ── Initialisation ──────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      // TFLite anti-spoof model (optional)
      if (_config.enableTFLite) {
        try {
          String? modelPath = _config.tfliteModelPath;

          // Resolve download URL: prefer user-supplied, fall back to bundled default
          final downloadUrl = _config.tfliteModelUrl ?? TFLiteModelDownloader.bundledModelUrl;

          // Auto-download when no local path is set
          if (modelPath == null) {
            final downloader = TFLiteModelDownloader(
              modelUrl: downloadUrl,
              onProgress: (p) {
                _tfliteModelDownloadProgress = p;
                notifyListeners();
              },
            );
            modelPath = await downloader.ensureModel();
            _tfliteModelDownloadProgress = null;
            notifyListeners();
          }

          // Resolve input size: prefer user-supplied, otherwise use bundled model's size
          final inputSize = _config.tfliteInputSize ??
              (_config.tfliteModelPath == null && _config.tfliteModelUrl == null
                  ? TFLiteModelDownloader.bundledInputSize
                  : 128);

          _tflite = TFLiteService(modelPath: modelPath, inputSize: inputSize);
          final loaded = await _tflite!.load();
          if (!loaded) {
            // Corrupted or wrong model — wipe the cache so next launch re-downloads
            if (!modelPath.startsWith('assets/')) {
              await TFLiteModelDownloader.clearCache();
              debugPrint('[LivenessController] Corrupted TFLite cache cleared — will re-download next launch');
            }
            _tfliteWarning = 'TFLite model failed to load (cache cleared — restart to re-download)';
            _tflite = null;
          }
        } catch (e) {
          debugPrint('[LivenessController] TFLite unavailable this session: $e');
          _tfliteWarning = 'TFLite unavailable: $e';
          _tflite = null;
          _tfliteModelDownloadProgress = null;
        }
      }

      // MiniFASNet video-replay detection model (optional)
      if (_config.enableVideoReplayDetection) {
        try {
          String? modelPath = _config.videoReplayModelPath;
          final downloadUrl = _config.videoReplayModelUrl ??
              VideoReplayModelDownloader.bundledModelUrl;
          if (modelPath == null) {
            final downloader = VideoReplayModelDownloader(
              modelUrl: downloadUrl,
              onProgress: (p) {
                _tfliteModelDownloadProgress = p;
                notifyListeners();
              },
            );
            modelPath = await downloader.ensureModel();
            _tfliteModelDownloadProgress = null;
            notifyListeners();
          }
          final inputSize = _config.videoReplayInputSize ??
              (_config.videoReplayModelPath == null &&
                      _config.videoReplayModelUrl == null
                  ? VideoReplayModelDownloader.bundledInputSize
                  : 80);
          _videoReplay = TFLiteService(
            modelPath: modelPath,
            inputSize: inputSize,
            realClassIndex: VideoReplayModelDownloader.bundledRealClassIndex,
          );
          final loaded = await _videoReplay!.load();
          if (!loaded) {
            if (!modelPath.startsWith('assets/')) {
              await VideoReplayModelDownloader.clearCache();
            }
            debugPrint('[LivenessController] VideoReplay model failed to load');
            _videoReplay = null;
          }
        } catch (e) {
          debugPrint('[LivenessController] VideoReplay unavailable: $e');
          _videoReplay = null;
          _tfliteModelDownloadProgress = null;
        }
      }

      // FaceNet face identity — auto-downloads model on first run (optional).
      // Failure is isolated: a bad download or corrupted cache disables Face ID
      // for this session but does not block camera or liveness from starting.
      if (_config.enableFaceId) {
        try {
          _faceIdentity = FaceIdentityService(
            similarityThreshold: _config.faceIdSimilarityThreshold,
          );
          await _faceIdentity!.initialize(
            onModelDownloadProgress: (p) {
              _faceIdModelDownloadProgress = p;
              notifyListeners();
            },
          );
          _faceIdModelDownloadProgress = null;
          notifyListeners();
        } catch (e) {
          debugPrint('[LivenessController] FaceId unavailable this session: $e');
          _faceIdentity = null;
          _faceIdModelDownloadProgress = null;
        }
      }

      _engine = LivenessEngine(
        requiredActions: _actions,
        config: _config,
        onActionCompleted: (_) => notifyListeners(),
        onStatusChanged:   (_) => notifyListeners(),
        onAllActionsCompleted: (r) => _onEngineComplete(r),
      );

      final camera = await _cameraService.getFrontCamera();
      if (camera == null) {
        _error = 'No front camera available';
        notifyListeners();
        return;
      }

      await _cameraService.initialize(
        camera: camera,
        config: _config,
        onFrame: (image) => _processFrame(image, camera),
      );

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _error = 'Camera initialization failed: $e';
      notifyListeners();
    }
  }

  // ── Per-frame pipeline ──────────────────────────────────────────────────

  Future<void> _processFrame(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_isDisposed || !_isInitialized) return;

    final result = await _faceDetector.processCameraImage(
      image,
      camera.sensorOrientation,
      camera.lensDirection,
      captureRawFrame: _config.enableFaceId || _config.enableTFLite,
    );

    if (_isDisposed) return;

    _currentFace  = result.faces.isNotEmpty ? result.faces.first : null;
    _lastQuality  = result.quality;
    if (result.rawFrame != null) _lastRawFrame = result.rawFrame;

    // Fire TFLite anti-spoof inference async; result is stored in _lastTfliteScore
    // and attached to LivenessResult at session end. Guard with _isTfliteRunning
    // so frames don't queue up if inference is slower than the camera rate.
    final rawForTflite  = result.rawFrame ?? _lastRawFrame;
    final faceForTflite = _currentFace;
    if (_tflite != null && !_isTfliteRunning) {
      if (rawForTflite == null) {
        debugPrint('[LivenessController] TFLite skip — rawFrame null');
      } else if (faceForTflite == null) {
        debugPrint('[LivenessController] TFLite skip — no face detected');
      } else {
        _isTfliteRunning = true;
        _tfliteFuture = _tflite!.run(
          imageBytes:        rawForTflite.imageBytes,
          imageWidth:        rawForTflite.imageWidth,
          imageHeight:       rawForTflite.imageHeight,
          faceBoundingBox:   faceForTflite.boundingBox,
          sensorOrientation: rawForTflite.sensorOrientation,
        ).then((tfliteResult) {
          if (_isDisposed) return;
          _isTfliteRunning = false;
          if (tfliteResult != null) {
            _lastTfliteScore = tfliteResult.realScore;
            if (_tfliteWarning != null) {
              _tfliteWarning = null;  // clear stale warning once inference succeeds
              notifyListeners();
            }
          } else {
            _tfliteWarning = 'TFLite inference failed — see console for [TFLiteService] error';
            notifyListeners();
          }
          _tfliteFuture = null;
        });
        unawaited(_tfliteFuture!);
      }
    }

    // Video-replay inference (MiniFASNet) — same guard pattern as TFLite
    if (_videoReplay != null && !_isVideoReplayRunning) {
      if (rawForTflite != null && faceForTflite != null) {
        _isVideoReplayRunning = true;
        _videoReplayFuture = _videoReplay!.run(
          imageBytes:        rawForTflite.imageBytes,
          imageWidth:        rawForTflite.imageWidth,
          imageHeight:       rawForTflite.imageHeight,
          faceBoundingBox:   faceForTflite.boundingBox,
          sensorOrientation: rawForTflite.sensorOrientation,
        ).then((r) {
          if (_isDisposed) return;
          _isVideoReplayRunning = false;
          if (r != null) _lastVideoReplayScore = r.realScore;
          _videoReplayFuture = null;
        });
        unawaited(_videoReplayFuture!);
      }
    }

    _engine?.processFrame(result.faces, quality: result.quality);
    notifyListeners();
  }

  Future<void> _onEngineComplete(LivenessResult result) async {
    var finalResult = result;

    // If a TFLite inference is still running, wait for it before reading the score.
    // Without this await the score is always null (race condition: session completes
    // on the same frame that fired the last unawaited inference).
    if (_isTfliteRunning && _tfliteFuture != null) {
      await _tfliteFuture;
    }

    // Await any in-flight video-replay inference
    if (_isVideoReplayRunning && _videoReplayFuture != null) {
      await _videoReplayFuture;
    }

    // Attach video-replay score to result
    if (_lastVideoReplayScore != null) {
      final isReplay = _lastVideoReplayScore! < _config.videoReplayThreshold;
      finalResult = finalResult.withVideoReplayResult(
        _lastVideoReplayScore!,
        videoReplayDetected: isReplay,
      );
      if (isReplay) {
        debugPrint('[LivenessController] Video replay attack detected — score=${_lastVideoReplayScore!.toStringAsFixed(3)}');
      }
    }

    // Attach TFLite score + deepfake flag to the result
    if (_lastTfliteScore != null) {
      final isDeepfake = _lastTfliteScore! < _config.tfliteDeepfakeThreshold;
      finalResult = finalResult.withTfliteResult(
        _lastTfliteScore!,
        deepfakeDetected: isDeepfake,
      );
      if (isDeepfake) {
        debugPrint('[LivenessController] Deepfake flagged — tfliteScore=${_lastTfliteScore!.toStringAsFixed(3)} < threshold=${_config.tfliteDeepfakeThreshold}');
      }
    }

    // Resolve persistent faceId after successful liveness
    if (result.isSuccess && _faceIdentity != null && _currentFace != null) {
      final raw = _lastRawFrame;
      if (raw != null) {
        final match = await _faceIdentity!.identifyFromFrame(
          imageBytes:        raw.imageBytes,
          imageWidth:        raw.imageWidth,
          imageHeight:       raw.imageHeight,
          faceBoundingBox:   _currentFace!.boundingBox,
          sensorOrientation: raw.sensorOrientation,
        );
        if (match != null) {
          finalResult = finalResult.withFaceId(match.faceId, isNew: match.isNew);
        }
      }
    }

    if (finalResult.isSuccess) {
      onSuccess(finalResult);
    } else {
      onFailed(finalResult.failureReason ?? 'Liveness check failed');
    }
    notifyListeners();
  }

  // ── Reset / Dispose ─────────────────────────────────────────────────────

  Future<void> reset() async {
    if (!_isInitialized) return;
    _engine?.reset(_actions);
    _currentFace                 = null;
    _lastQuality                 = null;
    _lastRawFrame                = null;
    _lastTfliteScore             = null;
    _isTfliteRunning             = false;
    _tfliteFuture                = null;
    _tfliteModelDownloadProgress = null;
    _lastVideoReplayScore        = null;
    _isVideoReplayRunning        = false;
    _videoReplayFuture           = null;
    notifyListeners();
  }

  /// Clear all stored face embeddings on this device (e.g. on user logout).
  Future<void> clearFaceIdentities() async {
    await _faceIdentity?.clearAllFaces();
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await _cameraService.dispose();
    await _faceDetector.dispose();
    _tflite?.dispose();
    _videoReplay?.dispose();
    _faceIdentity?.dispose();
    _engine?.dispose();
    super.dispose();
  }
}

